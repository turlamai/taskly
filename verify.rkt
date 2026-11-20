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
         glaze/tray/main
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

;; Open the in-page journey harness gate for this verifier only.
(putenv "TASKLY_E2E" "1")

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
   #:events event-bus
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
     (define url-ok? (equal? (webview-url wv) url))
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
     ;; ---- slice 3: thin-host capabilities in the real window ----
     (install-host! wv url)
     (define sc-ok
       (post-json url "api/host/shortcut" (hasheq 'accelerator "Ctrl+Alt+T")))
     (define sc-registered (host-shortcut-registered?))
     (define sc-bad
       (post-json url "api/host/shortcut" (hasheq 'accelerator "Ctrl+NotAKey")))
     (define sc-re
       (post-json url "api/host/shortcut" (hasheq 'accelerator "Ctrl+Alt+T")))
     (define autostart (post-json url "api/host/autostart" (hasheq)))
     (define autostart-dev
       (post-json url "api/host/autostart_set" (hasheq 'enabled #t)))
     ;; Declared platform exception (PRODUCT-SPEC §6): macOS CI sessions
     ;; grant no global-hotkey trust (TCC / agent session), so live
     ;; registration is asserted on Windows + Linux; macOS asserts the
     ;; API contract (valid shape accepted-or-denied structurally, invalid
     ;; accelerator rejected with the engine message).
     (define macos? (eq? (system-type 'os) 'macosx))
     ;; Quick-capture popup: second real window on the #capture route.
     (post-json url "api/rpc/open_database"
                (hasheq 'path (path->string (build-path db-folder "taskly.sqlite"))))
     (host-open-capture!)
     (define cap-wv (host-capture-window))
     (define cap-deadline (+ (current-inexact-milliseconds) 15000))
     (define cap-loaded?
       (let loop ()
         (cond
           [(and cap-wv (equal? (webview-title cap-wv) "Taskly Capture Ready")) #t]
           [(>= (current-inexact-milliseconds) cap-deadline) #f]
           [else (sleep 0.1) (loop)])))
     (define cap-shot (and cap-wv (webview-capture! cap-wv)))
     (define saved-cap-shot
       (cond
         [(and cap-shot (file-exists? cap-shot))
          (make-directory* evidence-dir)
          (define dest (build-path evidence-dir "taskly-capture.png"))
          (copy-file cap-shot dest #:exists-ok? #t)
          dest]
         [else #f]))
     (define cap-done (post-json url "api/host/capture_done" (hasheq)))
     (sleep 0.8)
     (define cap-closed? (and cap-wv (webview-closed? cap-wv)))
     ;; ---- slice 5: in-page PRODUCT-SPEC §6 journey harness ----
     ;; Same real window, fresh document load on the #e2e route (a bare
     ;; hash change would not re-run the page); the host gate is open only
     ;; because this verifier sets TASKLY_E2E=1 (production pages inert).
     (webview-navigate wv (string-append url "?e2e=1#e2e"))
     (define e2e-deadline (+ (current-inexact-milliseconds) 180000))
     (define e2e-reports
       (let loop ()
         (define state (post-json url "api/host/e2e" (hasheq)))
         (define reps (and (hash? state) (hash-ref state 'reports '())))
         (cond
           [(and (list? reps)
                 (for/or ([r (in-list reps)])
                   (and (hash? r) (equal? (hash-ref r 'id "") "done"))))
            reps]
           [(>= (current-inexact-milliseconds) e2e-deadline) reps]
           [else (sleep 0.5) (loop)])))
     (define (e2e-ok? jid)
       (and (list? e2e-reports)
            (for/or ([r (in-list e2e-reports)])
              (and (hash? r) (equal? (hash-ref r 'id "") jid)
                   (eq? #t (hash-ref r 'ok #f))))))
     (for ([r (in-list (if (list? e2e-reports) e2e-reports '()))])
       (when (hash? r)
         (printf "[verify:e2e] ~a ok=~a ~a\n"
                 (hash-ref r 'id "?") (hash-ref r 'ok #f) (hash-ref r 'detail ""))))
     (define e2e-shot (webview-capture! wv))
     (define saved-e2e-shot
       (cond
         [(and e2e-shot (file-exists? e2e-shot))
          (make-directory* evidence-dir)
          (define dest (build-path evidence-dir "taskly-e2e.png"))
          (copy-file e2e-shot dest #:exists-ok? #t)
          dest]
         [else #f]))
     (set! verdicts
           (list (cons 'page-loaded loaded?)
                 (cons 'url url-ok?)
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
                                           (string-contains? (hash-ref missing 'error "") "not found")))
                 (cons 'shortcut-register (or macos?
                                              (and (hash? sc-ok) (eq? #t (hash-ref sc-ok 'ok #f))
                                                   (equal? "Ctrl+Alt+T" (hash-ref sc-ok 'accelerator #f)))))
                 (cons 'shortcut-live (or macos? sc-registered))
                 (cons 'shortcut-invalid (and (hash? sc-bad)
                                              (string-contains? (hash-ref sc-bad 'error "") "invalid accelerator")))
                 (cons 'shortcut-reregister (or macos?
                                                (and (hash? sc-re) (eq? #t (hash-ref sc-re 'ok #f)))))
                 (cons 'autostart-get (and (hash? autostart) (hash-has-key? autostart 'enabled)
                                           (eq? #f (hash-ref autostart 'installed #t))))
                 (cons 'autostart-dev-guard (and (hash? autostart-dev)
                                                 (string-contains? (hash-ref autostart-dev 'error "") "installed build")))
                 (cons 'tray (or (not (tray-supported?)) (host-tray-live?)))
                 (cons 'capture-loaded cap-loaded?)
                 (cons 'capture-shot (and saved-cap-shot (> (file-size saved-cap-shot) 0)))
                 (cons 'capture-done (eq? #t cap-done))
                 (cons 'capture-closed cap-closed?)
                 (cons 'e2e-setup (e2e-ok? "setup"))
                 (cons 'e2e-j01 (e2e-ok? "j01-quick-edit-escape"))
                 (cons 'e2e-j02 (e2e-ok? "j02-quick-edit-return"))
                 (cons 'e2e-j03 (e2e-ok? "j03-quick-edit-save"))
                 (cons 'e2e-j04 (e2e-ok? "j04-quick-edit-save-failure"))
                 (cons 'e2e-j05 (e2e-ok? "j05-quick-edit-cancel"))
                 (cons 'e2e-j06 (e2e-ok? "j06-detail-field-change"))
                 (cons 'e2e-j07 (e2e-ok? "j07-detail-persist-failure"))
                 (cons 'e2e-j08 (e2e-ok? "j08-detail-close-persisted"))
                 (cons 'e2e-j09 (e2e-ok? "j09-delete-undo"))
                 (cons 'e2e-j10 (e2e-ok? "j10-delete-timeout"))
                 (cons 'e2e-j11 (e2e-ok? "j11-search-refresh"))
                 (cons 'e2e-j12 (e2e-ok? "j12-database-switch"))
                 (cons 'e2e-j13 (e2e-ok? "j13-gate-create-collision"))
                 (cons 'e2e-j14 (e2e-ok? "j14-recovery-missing-retry-relocate"))
                 (cons 'e2e-j15 (e2e-ok? "j15-migrate-success-collision-failure"))
                 (cons 'e2e-j16 (e2e-ok? "j16-backup-export-restore-refused"))
                 (cons 'e2e-j17 (e2e-ok? "j17-new-task-default-list"))
                 (cons 'e2e-done (e2e-ok? "done"))
                 (cons 'e2e-shot (and saved-e2e-shot (> (file-size saved-e2e-shot) 0)))))
     (webview-close wv))))

(stop)
(host-teardown!)
(for ([verdict (in-list verdicts)])
  (printf "[verify] ~a = ~a\n" (car verdict) (cdr verdict)))
(unless (and (pair? verdicts) (andmap cdr verdicts))
  (eprintf "[verify] native UI verification failed\n")
  (exit 1))
(displayln "[verify] ALL PASS")