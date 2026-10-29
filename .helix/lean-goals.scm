;; Lean goal pane: shows the goals and hypotheses at the cursor in a pane on the right.
;;
;; Uses Lean's own `$/lean/plainGoal` (tactic mode) and `$/lean/plainTermGoal` (term mode)
;; requests, so it works with plain `lake serve` as well as `lean-prism serve`.

(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/components.scm")
(require (prefix-in helix.static. "helix/static.scm"))

(provide lean-goals-enable!
         lean-goals-toggle)

;; Width of the pane in columns, including the separator.
(define *width* 50)
;; Wait this long after the last cursor movement or edit before asking Lean, so that
;; holding `j` doesn't send a request per line.
(define *debounce-ms* 75)
;; Language servers that answer Lean's goal requests, in order of preference.
(define *servers* '("lean-prism" "lean"))

(define *enabled* #f)
;; Lines currently shown in the pane.
(define *lines* '("Move the cursor into a proof."))
;; Bumped on every cursor movement / edit. A pending update only fires if it's still the latest,
;; and a response is only shown if no newer request has been answered already.
(define *tick* 0)
(define *shown-tick* 0)

;;; Rendering

(define (wrap line width)
  (if (<= (string-length line) width)
      (list line)
      (cons (substring line 0 width) (wrap (substring line width (string-length line)) width))))

(define (render _state rect buf)
  (when *enabled*
    (let* ([x (- (area-width rect) *width*)]
           ;; Leave the command line at the bottom alone.
           [height (- (area-height rect) 1)]
           [text-style (theme-scope "ui.text")]
           [sep-style (theme-scope "ui.window")]
           [rows (apply append (map (lambda (l) (wrap l (- *width* 2))) *lines*))])
      (buffer/clear-with buf (area x 0 *width* height) (theme-scope "ui.background"))
      (let loop ([y 0])
        (when (< y height)
          (frame-set-string! buf x y "│" sep-style)
          (loop (+ y 1))))
      (let loop ([y 0] [rows rows])
        (when (and (< y height) (not (null? rows)))
          (frame-set-string! buf (+ x 2) y (car rows) text-style)
          (loop (+ y 1) (cdr rows)))))))

(define (pass-through _state _event)
  event-result/ignore)

(define (show-pane!)
  (set-editor-clip-right! *width*)
  (push-component! (new-component! "lean-goals" #f render (hash "handle_event" pass-through))))

(define (hide-pane!)
  (set-editor-clip-right! 0)
  (pop-last-component-by-name! "lean-goals"))

;;; Requests

(define (lean-buffer?)
  (equal? (editor-document->language (editor->doc-id (editor-focus))) "lean"))

(define (active-server)
  (let ([names (map lsp-client-name (get-active-lsp-clients))])
    (let loop ([candidates *servers*])
      (cond
        [(null? candidates) #f]
        [(member (car candidates) names) (car candidates)]
        [else (loop (cdr candidates))]))))

(define (show! tick lines)
  (when (>= tick *shown-tick*)
    (set! *shown-tick* tick)
    (set! *lines* lines)))

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

(define (schedule-update . _args)
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

;;; Entry points

(define *hooks-registered* #f)

;;@doc
;; Show the Lean goal pane and keep it updated on cursor movement and edits.
(define (lean-goals-enable!)
  (unless *hooks-registered*
    (set! *hooks-registered* #t)
    (register-hook "selection-did-change" schedule-update)
    (register-hook "document-changed" schedule-update))
  (unless *enabled*
    (set! *enabled* #t)
    (show-pane!)
    ;; init.scm runs before any file is opened, when there is no view to look at yet.
    (enqueue-thread-local-callback schedule-update)))

;;@doc
;; Show or hide the Lean goal pane.
(define (lean-goals-toggle)
  (if *enabled*
      (begin
        (set! *enabled* #f)
        (hide-pane!))
      (lean-goals-enable!)))
