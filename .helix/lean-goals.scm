;; Lean goal pane: shows the tactic state and expected type at the cursor, like VS Code's
;; infoview, in a split on the right.
;;
;; Only needs the plain `lake serve` language server:
;; - `$/lean/plainGoal`: the tactic state,
;; - `$/lean/plainTermGoal`: the expected type of the term.
;;
;; The pane is an ordinary Helix split showing a file that this plugin rewrites and reloads,
;; so window navigation (`Space w l`, `Ctrl-w h`…), selections and yanking work in it as in any
;; other buffer. Reloading (rather than editing the buffer) keeps it unmodified, so `:q` works.

(require-builtin steel/time)
(require "helix/editor.scm")
(require "helix/misc.scm")
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))

(provide lean-goals-enable!
         lean-goals-toggle)

;; Wait this long after the last cursor movement or edit before asking Lean, so that
;; holding `j` doesn't send a request per line.
(define *debounce-ms* 75)
;; Show whatever has arrived after this long, even if some request hasn't been answered.
;; (A failed request never calls back.)
(define *timeout-ms* 1000)
;; Name of the Lean language server in languages.toml.
(define *server* "lean")

;; The file shown in the pane. One per Helix instance, so several editors don't fight over it.
(define *tmp-prefix* "/tmp/lean-goals-")
(define *path* (string-append *tmp-prefix* (number->string (current-milliseconds)) "/goals"))

(define *enabled* #f)
;; Document shown in the pane, once it has been opened.
(define *doc* #f)
;; Lines currently written to the pane's file.
(define *lines* '("-- Move the cursor into a proof."))
;; Bumped on every cursor movement / edit; responses to older requests are dropped.
(define *tick* 0)
;; Answers for the current tick so far: section name -> lines, or #f if there's nothing to show.
(define *answers* (hash))
(define *sections* '(tactic term))

;;; The pane

(define (write-goals-file!)
  (let ([dir (parent-name *path*)])
    (unless (path-exists? dir)
      (create-directory! dir)))
  (when (path-exists? *path*)
    (delete-file! *path*))
  (let ([port (open-output-file *path*)])
    (for-each (lambda (line)
                (write-string line port)
                (write-string "\n" port))
              *lines*)
    (close-output-port port)))

;; The view showing the pane, or #f if the user closed it.
(define (pane-view)
  (and *doc* (editor-doc-exists? *doc*) (editor-doc-in-view? *doc*)))

;; Helix reloads the plugin with fresh state (e.g. after trusting the workspace), leaving the
;; previous instance's pane open. Take that pane over instead of opening a second one.
(define (adopt-existing-pane!)
  (let loop ([docs (editor-all-documents)])
    (unless (null? docs)
      (let ([path (editor-document->path (car docs))])
        (if (and path
                 (starts-with? path *tmp-prefix*)
                 (editor-doc-in-view? (car docs)))
            (begin
              (set! *doc* (car docs))
              (set! *path* path))
            (loop (cdr docs)))))))

(define (show-pane!)
  (unless (pane-view)
    (adopt-existing-pane!))
  (unless (pane-view)
    (write-goals-file!)
    (let ([code-view (editor-focus)])
      ;; Opens to the right of the focused view and focuses it.
      (helix.vsplit *path*)
      (set! *doc* (editor->doc-id (editor-focus)))
      (editor-set-focus! code-view))))

(define (hide-pane!)
  (let ([view (pane-view)])
    (when view
      (let ([code-view (editor-focus)])
        (editor-set-focus! view)
        (helix.buffer-close!)
        (when (not (equal? code-view view))
          (editor-set-focus! code-view))))))

(define (show! lines)
  (unless (equal? lines *lines*)
    (set! *lines* lines)
    (when (pane-view)
      (write-goals-file!)
      (editor-document-reload *doc*))))

;;; Rendering
;;
;; Section headings are written as Lean comments.

(define (lines s)
  (split-many s "\n"))

(define (render)
  (let* ([section (lambda (key heading)
                    (let ([body (hash-try-get *answers* key)])
                      (if body
                          (append (list heading) body '(""))
                          '())))]
         [out (append (section 'tactic "-- Tactic state")
                      (section 'term "-- Expected type"))])
    (show! (if (null? out) '("-- Nothing at the cursor") out))))

;; `$/lean/plainGoal`: {goals: [string]}. JSON arrives as hashes keyed by symbols, arrays as lists.
(define (tactic-lines result)
  (and (hash? result)
       (list? (hash-try-get result 'goals))
       (let ([goals (hash-ref result 'goals)])
         (if (null? goals)
             '("No goals")
             ;; Separate several goals with a blank line.
             (let loop ([goals goals] [acc '()])
               (if (null? (cdr goals))
                   (append acc (lines (car goals)))
                   (loop (cdr goals) (append acc (lines (car goals)) '("")))))))))

;; `$/lean/plainTermGoal`: {goal: string, range}.
(define (term-lines result)
  (and (hash? result)
       (string? (hash-try-get result 'goal))
       (lines (hash-ref result 'goal))))

;;; Requests

(define (lean-buffer?)
  (equal? (editor-document->language (editor->doc-id (editor-focus))) "lean"))

;; The server name if it's attached to the focused buffer (it may still be starting).
(define (active-server)
  (and (lean-buffer?)
       (member *server* (map lsp-client-name (get-active-lsp-clients)))
       *server*))

;; Set once the current tick's timeout has passed: from then on, render every late answer.
(define *timed-out* #f)

(define (answer! tick key to-lines result)
  (when (= tick *tick*)
    (set! *answers*
          (hash-insert *answers*
                       key
                       (with-handler (lambda (err)
                                       (list (to-string "lean-goals: couldn't read the answer: " err)))
                                     (to-lines result))))
    (when (or *timed-out* (= (hash-length *answers*) (length *sections*)))
      (render))))

;; Send a request only while the focused buffer still talks to Lean; by the time an earlier
;; response arrives the user may have moved to the pane or another file.
(define (request tick method params on-result)
  (when (and (= tick *tick*) (active-server))
    (send-lsp-command *server* method params on-result)))

(define (request-all tick)
  (let ([path (helix.static.cx->current-file)])
    (when (and (active-server) path)
      (let* ([lsp-pos (helix.static.offset->lsp "utf-16" (cursor-position))]
             [uri (string-append "file://" path)]
             [pos (hash "line" (list-ref lsp-pos 0) "character" (list-ref lsp-pos 1))]
             [params (hash "textDocument" (hash "uri" uri) "position" pos)])
        (set! *answers* (hash))
        (set! *timed-out* #f)
        (request tick "$/lean/plainGoal" params
                 (lambda (r) (answer! tick 'tactic tactic-lines r)))
        (request tick "$/lean/plainTermGoal" params
                 (lambda (r) (answer! tick 'term term-lines r)))
        (enqueue-thread-local-callback-with-delay
         *timeout-ms*
         (lambda ()
           (when (= tick *tick*)
             (set! *timed-out* #t)
             (when (< (hash-length *answers*) (length *sections*))
               (render)))))))))

(define (schedule-update)
  (when (and *enabled* (lean-buffer?))
    (set! *tick* (+ *tick* 1))
    (let ([tick *tick*])
      (enqueue-thread-local-callback-with-delay
       *debounce-ms*
       (lambda ()
         ;; Only the last movement within the debounce window sends a request.
         (when (and (= tick *tick*) (lean-buffer?))
           (with-handler (lambda (err) (set-error! (to-string "lean-goals: " err)))
                         (request-all tick))))))))

(define (on-selection-change _view)
  (schedule-update))

;; Reloading the pane's own document fires this too; don't answer it with another request.
(define (on-document-change doc _old-text)
  (unless (equal? doc *doc*)
    (schedule-update)))

;;; Entry points

(define *hooks-registered* #f)

;;@doc
;; Show the Lean goal pane and keep it updated on cursor movement and edits.
(define (lean-goals-enable!)
  (unless *hooks-registered*
    (set! *hooks-registered* #t)
    (register-hook "selection-did-change" on-selection-change)
    (register-hook "document-changed" on-document-change))
  (set! *enabled* #t)
  ;; init.scm runs before any file is opened, when there is no view to split yet.
  (enqueue-thread-local-callback
   (lambda ()
     (with-handler (lambda (err) (set-error! (to-string "lean-goals: " err)))
                   (show-pane!))
     (schedule-update))))

;;@doc
;; Show or hide the Lean goal pane.
(define (lean-goals-toggle)
  (if (and *enabled* (pane-view))
      (begin
        (set! *enabled* #f)
        (hide-pane!))
      (lean-goals-enable!)))
