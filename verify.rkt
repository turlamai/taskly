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
     (set! verdicts
           (list (cons 'page-loaded loaded?)
                 (cons 'url (equal? (webview-url wv) url))
                 (cons 'capture (and saved-shot (> (file-size saved-shot) 0)))
                 (cons 'health-ok (and (hash? health) (hash-ref health 'ok #f)))
                 (cons 'default-db (and (string? default-db)
                                        (non-empty-string? default-db)))))
     (webview-close wv))))

(stop)
(for ([verdict (in-list verdicts)])
  (printf "[verify] ~a = ~a\n" (car verdict) (cdr verdict)))
(unless (and (pair? verdicts) (andmap cdr verdicts))
  (eprintf "[verify] native UI verification failed\n")
  (exit 1))
(displayln "[verify] ALL PASS")