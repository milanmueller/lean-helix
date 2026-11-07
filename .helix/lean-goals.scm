;; Lean goal pane: shows the goals and hypotheses at the cursor in a split on the right.
;;
;; Uses Lean's own `$/lean/plainGoal` (tactic mode) and `$/lean/plainTermGoal` (term mode)
;; requests, so it only needs the plain `lake serve` language server.
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
;; Name of the Lean language server in languages.toml.
(define *server* "lean")

;; The file shown in the pane. One per Helix instance, so several editors don't fight over it.
(define *tmp-prefix* "/tmp/lean-goals-")
(define *path* (string-append *tmp-prefix* (number->string (current-milliseconds)) "/goals"))

(define *enabled* #f)
;; Document shown in the pane, once it has been opened.
(define *doc* #f)
;; Lines currently written to the pane's file.
(define *lines* '("Move the cursor into a proof."))
;; Bumped on every cursor movement / edit. A pending update only fires if it's still the latest,
;; and a response is only shown if no newer request has been answered already.
(define *tick* 0)
(define *shown-tick* 0)

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

(define (refresh-pane!)
  (when (pane-view)
    (write-goals-file!)
    (editor-document-reload *doc*)))

;;; Requests

(define (lean-buffer?)
  (equal? (editor-document->language (editor->doc-id (editor-focus))) "lean"))

;; The server name if it's attached to the current buffer (it may still be starting).
(define (active-server)
  (and (member *server* (map lsp-client-name (get-active-lsp-clients))) *server*))

(define (show! tick lines)
  (when (>= tick *shown-tick*)
    (set! *shown-tick* tick)
    (unless (equal? lines *lines*)
      (set! *lines* lines)
      (refresh-pane!))))

;; JSON responses arrive as hashes keyed by symbols, with arrays as lists.
(define (goal-lines result)
  (cond
    [(not (hash? result)) #f]
    [(hash-contains? result 'goals)
     (let ([goals (hash-ref result 'goals)])
       (cond
         [(not (list? goals)) #f]
         [(null? goals) '("No goals")]
         ;; Separate several goals with a blank line.
         [else (apply append (map (lambda (g) (append (split-many g "\n") '(""))) goals))]))]
    [(hash-contains? result 'goal) (cons "Expected type:" (split-many (hash-ref result 'goal) "\n"))]
    [else #f]))

(define (request-goals tick)
  (let ([server (active-server)]
        [path (helix.static.cx->current-file)])
    (when (and server path)
      (let* ([pos (helix.static.offset->lsp "utf-16" (cursor-position))]
             [params (hash "textDocument" (hash "uri" (string-append "file://" path))
                           "position" (hash "line" (list-ref pos 0) "character" (list-ref pos 1)))])
        (send-lsp-command
         server
         "$/lean/plainGoal"
         params
         (lambda (result)
           (let ([lines (goal-lines result)])
             (if lines
                 (show! tick lines)
                 ;; Not inside a tactic block: fall back to the expected type of the term.
                 (send-lsp-command server
                                   "$/lean/plainTermGoal"
                                   params
                                   (lambda (result)
                                     (show! tick (or (goal-lines result) '("No goal here")))))))))))))

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
                         (request-goals tick))))))))

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
