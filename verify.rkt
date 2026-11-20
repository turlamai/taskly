#lang racket/base

;; Real-window verification for the Taskly glaze host (#141, slice 1).
;; The family pattern (glaze docs/product-acceptance.md): wait for the
;; native window, check title/URL, capture a PNG, drive the typed routes
;; over the loopback HTTP adapter, then close. Slice 5 extends this into
;; the full first-run / persistence / restart journeys.
;;
;; Run: racket verify.rkt   (needs a graphical session; WebView2 runtime
;; on Windows, WKWebView on macOS, WebKitGTK + Xvfb on Linux CI).

(require glaze/app
         glaze/window
         json
         net/url
         racket/file
         racket/port
         racket/runtime-path
         racket/string
         "backend/main.rkt"
         "racket/taskly/paths.rkt")

(define-runtime-path frontend-dist "apps/desktop/dist")
(define-runtime-path evidence-dir ".glaze/verify")

;; Isolation: the verifier never touches the real ~/.taskly — the serve
;; thread inherits this parameter (same pattern as the wire tests).
(current-taskly-home (make-temporary-file "taskly-verify-~a" 'directory))

(define verdicts '())

;; Start the engine transport (the app's module+ main does the same).
(start-engine!)

(define (post-json base path body)
  (define url (string->url (string-append base path)))
  (define resp
    (post-pure-port url
                    (string->bytes/utf-8 (jsexpr->string body))
                    '("Content-Type: application/json")))
  (define text (port->string resp))
  (close-input-port resp)
  (with-handlers ([exn:fail? (lambda (_) text)])
    (string->jsexpr text)))

(define-values (_kind stop)
  (run-app
   #:public-dir frontend-dist
   #:api api
   #:transport 'http
   #:api-token #f
   #:title "Taskly"
   #:width 1100
   #:height 760
   #:on-ready
   (lambda (wv url)
     ;; Wait for the page (its <title> is Taskly).
     (define deadline (+ (current-inexact-milliseconds) 20000))
     (define loaded?
       (let loop ()
         (cond
           [(equal? (webview-title wv) "Taskly") #t]
           [(>= (current-inexact-milliseconds) deadline) #f]
           [else (sleep 0.1) (loop)])))
     ;; Give the boot flow (open/create default db + snapshot) a moment.
     (sleep 1.5)
     (define shot (and loaded? (webview-capture! wv)))
     (define saved-shot
       (cond
         [(and shot (file-exists? shot))
          (make-directory* evidence-dir)
          (define dest (build-path evidence-dir "taskly-window.png"))
          (copy-file shot dest #:exists-ok? #t)
          dest]
         [else #f]))
     ;; Drive the typed routes over the same adapter the page uses.
     (define health (post-json url "api/health" (hasheq)))
     (define default-db (post-json url "api/rpc/default_database" (hasheq)))
     ;; First-run journey through the real window's backend: the page
     ;; shows the startup gate (isolated home has no database), then the
     ;; typed routes exercise create → mutate → backup → close.
     (define db-folder (build-path (current-taskly-home) "journey"))
     (make-directory* db-folder)
     (define created (post-json url "api/rpc/create_database"
                                (hasheq 'folder (path->string db-folder) 'name "Verify")))
     (define added (post-json url "api/rpc/add_task"
                              (hasheq 'text "verify task" 'listId 'null
                                      'dueDate 'null 'dueTime 'null 'notes 'null)))
     (define task-id (and (hash? added) (hash-ref added 'id #f)))
     (define snap (post-json url "api/rpc/load_snapshot"
                             (hasheq 'view "all" 'listId 'null 'showCompleted #t)))
     (define done (post-json url "api/rpc/set_completed"
                             (hasheq 'id task-id 'completed #t)))
     (define renamed (post-json url "api/rpc/update_task_text"
                                (hasheq 'id task-id 'text "renamed")))
     (define deleted (post-json url "api/rpc/delete_task" (hasheq 'id task-id)))
     (define new-list (post-json url "api/rpc/create_list"
                                 (hasheq 'name "L2" 'icon 'null 'color 'null)))
     (define list-id (and (hash? new-list) (hash-ref new-list 'id #f)))
     (define list-deleted (post-json url "api/rpc/delete_list" (hasheq 'id list-id)))
     (define backup-path (build-path (current-taskly-home) "backup.json"))
     (define exported (post-json url "api/rpc/export_backup"
                                 (hasheq 'path (path->string backup-path))))
     (define preview (post-json url "api/rpc/preview_backup"
                                (hasheq 'path (path->string backup-path))))
     (define closed (post-json url "api/rpc/close_database" (hasheq)))
     ;; Negative path: the engine's message must reach the client (glaze
     ;; bad-param channel), so the UI can tell missing from corrupt.
     (define missing
       (post-json url "api/rpc/open_database"
                  (hasheq 'path (path->string (build-path (current-taskly-home) "nope.sqlite")))))
     (set! verdicts
           (list (cons 'page-loaded loaded?)
                 (cons 'url (equal? (webview-url wv) url))
                 (cons 'capture (and saved-shot (> (file-size saved-shot) 0)))
                 (cons 'health-ok (and (hash? health) (hash-ref health 'ok #f)))
                 (cons 'default-db (and (string? default-db)
                                        (non-empty-string? default-db)))
                 (cons 'create-db (and (hash? created) (list? (hash-ref created 'lists #f))))
                 (cons 'add-task (and (integer? task-id) task-id))
                 (cons 'snapshot (and (hash? snap)
                                      (= 1 (length (hash-ref snap 'tasks '())))))
                 (cons 'complete (and (hash? done) (eq? #t (hash-ref done 'completed #f))))
                 (cons 'rename (and (hash? renamed)
                                    (equal? "renamed" (hash-ref renamed 'text #f))))
                 (cons 'delete-task (eq? #t deleted))
                 (cons 'create-list (and (integer? list-id) list-id))
                 (cons 'delete-list (eq? #t list-deleted))
                 (cons 'export (and (integer? exported) exported))
                 (cons 'preview (and (hash? preview) (integer? (hash-ref preview 'taskCount #f))))
                 (cons 'close-db (eq? 'null closed))
                 (cons 'error-message (and (hash? missing)
                                           (string? (hash-ref missing 'error #f))
                                           (string-contains? (hash-ref missing 'error "") "not found")))))
     (webview-close wv))))

(stop)
(for ([verdict (in-list verdicts)])
  (printf "[verify] ~a = ~a\n" (car verdict) (cdr verdict)))
(unless (and (pair? verdicts) (andmap cdr verdicts))
  (eprintf "[verify] native UI verification failed\n")
  (exit 1))
(displayln "[verify] ALL PASS")