#lang racket/base

;; Release-kind acceptance suite (#58 slice 1): the N→N+1 update lifecycle
;; with data preservation, driven end-to-end at the backend boundary every
;; host shares. Rivet's manifest fetch hard-requires HTTPS (the production
;; feed is HTTPS-only), so the suite injects a loopback fetch that still
;; verifies the signed envelope — every step of the shipped pipeline runs,
;; including the managed worker's download and the AppImage in-place swap.
;; Host-side install arms (macOS zip swap, Windows cmd/MSI handoff) are
;; exercised by the release pipeline on every tag; the backend-owned arm —
;; the Linux AppImage swap — runs here for real. The invariant under
;; everything: ~/.taskly/tasks.db stays byte-identical and the seeded task
;; survives.

(require crypto
         crypto/all
         racket/file
         racket/list
         racket/port
         racket/tcp
         rackunit
         (only-in rivet/distribution
                  write-signed-manifest
                  verify-signed-manifest
                  update-manifest
                  update-artifact
                  update-artifact-url
                  updater-config
                  select-update
                  update-artifact-installer
                  update-candidate-manifest
                  update-candidate-artifact
                  update-candidate
                  update-manifest-version
                  download-update
                  sha256-file/hex)
         ;; Transport injection for a loopback feed: the managed updater
         ;; provides these parameters to tests only.
         (submod (lib "rivet/distribution/managed-updater.rkt") test-support)
         racket/path
         racket/string
         net/url
         "../taskly/config.rkt"
         "../taskly/db.rkt"
         "../taskly/model.rkt"
         "../taskly/paths.rkt"
         "../taskly/updater.rkt")

(use-all-factories!)

;; Rivet exports the file-level hash (sha256-file/hex); route in-memory
;; artifact bytes through a scratch file so the suite compares digests
;; with the exact function the verifier uses.
(define (sha256-bytes/hex bytes)
  (define scratch (make-temporary-file "taskly-release-sha-~a"))
  (dynamic-wind
    (lambda ()
      (call-with-output-file scratch #:exists 'truncate
        (lambda (out) (write-bytes bytes out))))
    (lambda () (sha256-file/hex scratch))
    (lambda () (delete-file scratch))))

(define (wait-until ready? who [timeout-ms 15000])
  (let loop ([deadline (+ (current-inexact-milliseconds) timeout-ms)])
    (cond
      [(ready?) (void)]
      [(> (current-inexact-milliseconds) deadline)
       (fail (string-append "timed out waiting for " who))]
      [else (sleep 0.05) (loop deadline)])))

;; Loopback feed: reserve a port first (manifest URLs must embed it), then
;; serve an assoc list of (path-substring . bytes) over HTTP — the same
;; transport the artifact downloads already test against.
(define (open-loopback)
  (tcp-listen 0 16 #f))

(define (loopback-port listener)
  (cadr (call-with-values (lambda () (tcp-addresses listener #t)) list)))

(define (serve-on! listener routes)
  (thread
   (lambda ()
     (let accept ()
       (define-values (cin cout) (tcp-accept listener))
       (thread
        (lambda ()
          (with-handlers ([exn:fail? (lambda (_) (void))])
            (define request-line (read-line cin 'return-linefeed))
            (let drain ()
              (define line (read-line cin 'return-linefeed))
              (unless (or (eof-object? line) (equal? line "")) (drain)))
            (define text request-line) ; read-line already yields a string
            (define route
              (for/first ([pair (in-list routes)]
                          #:when (regexp-match? (regexp-quote (car pair)) text))
                pair))
            (cond
              [route
               (define body (cdr route))
               (display "HTTP/1.1 200 OK\r\n" cout)
               (display (format "Content-Length: ~a\r\n" (bytes-length body))
                        cout)
               (display "Connection: close\r\n\r\n" cout)
               (write-bytes body cout)]
              [else
               (display
                "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                cout)])
            (flush-output cout)
            ;; Closing the input half first would block on the peer's EOF
            ;; (close-input-port waits; the client waits for the response —
            ;; a deadlock). The output half-close is the EOF signal.
            (close-output-port cout))))
       (accept)))))

;; A throwaway Ed25519 identity: the private half signs the feed, the
;; public half plays the role the embedded production key plays live.
(define (test-signing-key)
  (define priv (generate-private-key 'eddsa '((curve ed25519))))
  (values priv
          (datum->pk-key (pk-key->datum priv 'rkt-public) 'rkt-public)))

(define (wrapped-feed manifest priv)
  (define wrapped (open-output-bytes))
  (write-signed-manifest manifest priv update-key-id wrapped)
  (get-output-bytes wrapped))

;; A check config pinned one version behind the feed, matching the current
;; platform so select-update sees a realistic offer.
(define (check-config key version)
  (updater-config app-identifier version 'stable
                  (platform-symbol) (architecture-symbol)
                  key update-key-id 0 (* 100 1024 1024) #f))

;; The shipped check verifies the signed envelope; only the HTTPS URL gate
;; and the pinned key are bypassed for the loopback feed (the public half is
;; compile-time identity, so tests verify with their throwaway key). The
;; product's manifest URL stays https because the managed updater — like
;; the shipped configuration — refuses anything else at construction.
(define (check-with-loopback-feed! base pub)
  (parameterize ([current-update-base-url "https://dl.example/taskly"]
                 [current-managed-fetch-manifest
                  (lambda (_url _key
                          #:key-id [key-id #f]
                          #:trusted-keys [_trusted-keys '()]
                          #:maximum-bytes [_maximum-bytes (* 1024 1024)])
                    (define in
                      (get-pure-port
                       (string->url (string-append base "/update-manifest.json"))))
                    (define envelope (port->bytes in))
                    (close-input-port in)
                    (verify-signed-manifest (open-input-bytes envelope)
                                            pub
                                            #:key-id key-id))]
                 [current-managed-download (loopback-download base)])
    (perform-check!)))

(define (zip-artifact url bytes)
  (update-artifact (platform-symbol) (architecture-symbol)
                   url (sha256-bytes/hex bytes)
                   (bytes-length bytes) 'zip '()
                   ;; rivet #271: component #f = the plain whole-app artifact.
                   #f))

;; Signed manifests may only carry https artifact URLs, and the trust layer
;; enforces that while signing. Tests therefore keep the signed shape and
;; redirect the transport: the real downloader runs with the artifact URL
;; rewritten to the loopback server, keeping size/SHA-256 verification.
(define (loopback-download base)
  (lambda (config candidate destination
                  #:on-progress on-progress
                  #:progress-every [_progress-every #f])
    (define artifact (update-candidate-artifact candidate))
    (define redirected
      (struct-copy update-artifact artifact
                   [url (string-append
                         base "/"
                         (car (reverse (string-split
                                        (update-artifact-url artifact)
                                        "/"))))]))
    (download-update
     config
     (update-candidate (update-candidate-manifest candidate) redirected)
     destination
     #:on-progress on-progress
     #:progress-every 1)))

(define (appimage-artifact url bytes)
  (update-artifact (platform-symbol) (architecture-symbol)
                   url (sha256-bytes/hex bytes)
                   (bytes-length bytes) 'appimage '()
                   ;; rivet #271: component #f = the plain whole-app artifact.
                   #f))

;; A user profile with a real database (the seeded default list plus one
;; task) — the thing an update must never touch.
(define (seeded-home)
  (define home (make-temporary-file "taskly-release-home-~a" 'directory))
  (define db (open-taskly-db (build-path home ".taskly" "tasks.db")))
  (define default-list (car (db-lists db)))
  (db-add-task! db (task-item 0 (todo-list-id default-list)
                              "OTA survival probe" #f #f #f
                              "2026-10-23T00:00:00" #f #f
                              0 (list) (list) #f))
  (close-taskly-db db)
  home)

(define (database-sha home)
  (sha256-file/hex (build-path home ".taskly" "tasks.db")))

(define (task-survives? home)
  (define db (open-taskly-db (build-path home ".taskly" "tasks.db")))
  (define survived?
    (ormap (lambda (t) (equal? (task-item-text t) "OTA survival probe"))
           (db-tasks db)))
  (close-taskly-db db)
  survived?)

(test-case "a plain-http feed can never yield a candidate"
  ;; fetch-update-manifest is HTTPS-only by contract; the managed check
  ;; surfaces that gate as the error phase with no offer.
  (parameterize ([current-update-base-url "http://127.0.0.1:1"]
                 [current-taskly-home
                  (make-temporary-file "taskly-release-http-~a" 'directory)])
    (reset-update-state!)
    (define result (perform-check!))
    (check-equal? (hash-ref result 'status) "error")
    (check-equal? (hash-ref (update-state-snapshot) 'phase) "error")
    (check-false (hash-ref (update-state-snapshot) 'availableVersion))))

(test-case "a re-keyed or re-signed feed fails closed"
  (define-values (priv-a pub-a) (test-signing-key))
  (define-values (priv-b pub-b) (test-signing-key))
  (define manifest
    (update-manifest app-identifier "9.9.9" 7 'stable
                     "2026-10-09T00:00:00Z" "0.0.0" #f #t 100
                     (list (zip-artifact "https://dl.example/taskly-9.9.9.zip"
                                         (make-bytes 8 2)))))
  ;; The exact bytes, under their own key-id: the happy path every client
  ;; runs against the production feed.
  (check-not-exn
   (lambda ()
     (verify-signed-manifest (open-input-bytes (wrapped-feed manifest priv-a))
                             pub-a
                             #:key-id update-key-id)))
  ;; A different key-id must fail closed (the shipped clients pin ours).
  (check-exn exn:fail?
             (lambda ()
               (verify-signed-manifest
                (open-input-bytes (wrapped-feed manifest priv-a))
                pub-a
                #:key-id "some-other-key")))
  ;; The same key-id under a different trusted key (a re-signed feed from
  ;; a key rotation the client never adopted) must also fail closed.
  (check-exn exn:fail?
             (lambda ()
               (verify-signed-manifest
                (open-input-bytes (wrapped-feed manifest priv-b))
                pub-a
                #:key-id update-key-id))))

(test-case "rollout 0 gates the offer for every bucket"
  (define-values (priv pub) (test-signing-key))
  (define manifest
    (update-manifest app-identifier "9.9.9" 7 'stable
                     "2026-10-09T00:00:00Z" "0.0.0" #f #t 0
                     (list (zip-artifact "https://dl.example/taskly-9.9.9.zip"
                                         (make-bytes 8 3)))))
  (check-false (select-update (check-config pub "0.2.3") manifest)))

(test-case "the N→N+1 lifecycle preserves the database byte for byte"
  (define home (seeded-home))
  (define db-sha (database-sha home))
  (define artifact-bytes (make-bytes 4096 7))
  (define-values (priv pub) (test-signing-key))
  (define listener (open-loopback))
  (define base (format "http://127.0.0.1:~a" (loopback-port listener)))
  ;; The feed offers 9.9.9 (above the shipped 0.2.x); a 0.2.2 feed exists
  ;; only to prove the semver gate refuses downgrades.
  (define manifest
    (update-manifest app-identifier "9.9.9" 8 'stable
                     "2026-10-23T00:00:00Z" "0.0.0" #f #t 100
                     (list (zip-artifact
                            "https://dl.example/taskly-9.9.9-x64.zip"
                            artifact-bytes))))
  (define downgrade
    (update-manifest app-identifier "0.2.2" 6 'stable
                     "2026-10-01T00:00:00Z" "0.0.0" #f #t 100
                     (list (zip-artifact
                            "https://dl.example/taskly-0.2.2-x64.zip"
                            artifact-bytes))))
  (check-false (select-update (check-config pub "0.2.3") downgrade)
               "a downgrade offer violates the semver gate")
  (define server-thread
    (serve-on! listener
               (list (cons "update-manifest.json" (wrapped-feed manifest priv))
                     (cons "taskly-9.9.9-x64.zip" artifact-bytes))))
  (parameterize ([current-taskly-home home])
    (reset-update-state!)
    ;; The managed check fetches the signed envelope over loopback, verifies
    ;; it, and selects the matching artifact.
    (define checked (check-with-loopback-feed! base pub))
    (check-equal? (hash-ref checked 'status) "available")
    (check-equal? (hash-ref checked 'availableVersion) "9.9.9")
    (check-equal? (hash-ref checked 'installer) "zip")
    (check-equal? (hash-ref (update-state-snapshot) 'phase) "idle")
    (define data-dir (make-temporary-file "taskly-release-data-~a" 'directory))
    (start-download! data-dir)
    (wait-until (lambda ()
                  (equal? (hash-ref (update-state-snapshot) 'phase)
                          "downloaded"))
                "the downloaded phase")
    (define downloaded (hash-ref (update-state-snapshot) 'downloadedPath))
    (check-true (and downloaded (file-exists? downloaded)))
    (check-equal? (sha256-file/hex downloaded)
                  (sha256-bytes/hex artifact-bytes))
    (check-false
     (file-exists? (path-add-extension downloaded #".partial"))
     "the .partial must be renamed away, not left behind")
    (check-equal? (database-sha home) db-sha
                  "the update flow must not touch tasks.db")
    (check-true (task-survives? home) "the seeded task must survive")
    (reset-update-state!))
  (kill-thread server-thread)
  (tcp-close listener))

(test-case "a sha-mismatched artifact refuses to land"
  (define home (seeded-home))
  (define db-sha (database-sha home))
  (define-values (priv pub) (test-signing-key))
  (define listener (open-loopback))
  (define base (format "http://127.0.0.1:~a" (loopback-port listener)))
  ;; The manifest vouches for zeros; the server sends nines — the size
  ;; matches, the hash cannot.
  (define manifest
    (update-manifest app-identifier "9.9.9" 7 'stable
                     "2026-10-09T00:00:00Z" "0.0.0" #f #t 100
                     (list (zip-artifact
                            "https://dl.example/taskly-9.9.9-x64.zip"
                            (make-bytes 512 0)))))
  (define server-thread
    (serve-on! listener
               (list (cons "update-manifest.json" (wrapped-feed manifest priv))
                     (cons "taskly-9.9.9-x64.zip" (make-bytes 512 9)))))
  (parameterize ([current-taskly-home home])
    (reset-update-state!)
    (check-equal? (hash-ref (check-with-loopback-feed! base pub) 'status)
                  "available")
    (define data-dir (make-temporary-file "taskly-release-bad-~a" 'directory))
    (start-download! data-dir)
    (wait-until (lambda ()
                  (equal? (hash-ref (update-state-snapshot) 'phase) "error"))
                "the sha-mismatch error phase")
    (define destination
      (build-path data-dir "updates"
                  (string-append app-display-name "-9.9.9"
                                 (installer-extension))))
    (check-false (file-exists? destination)
                 "a rejected artifact must never reach the destination")
    (check-false
     (file-exists? (path-add-extension destination #".partial")))
    (check-equal? (database-sha home) db-sha)
    (check-true (task-survives? home))
    (reset-update-state!))
  (kill-thread server-thread)
  (tcp-close listener))

;; The AppImage target is read from $APPIMAGE, which is always a string.
;; Handing that string to `path->string` after the swap made a successful
;; in-place update report `path->string: contract violation` (taskly 0.2.6
;; audit). Guard the type on every platform, not only where the swap runs.
(test-case "the AppImage target stays a path end to end"
  (define image (make-temporary-file "taskly-appimage-target-~a.AppImage"))
  (call-with-output-file image #:exists 'truncate
    (lambda (out) (write-bytes #"" out)))
  (define had-appimage (getenv "APPIMAGE"))
  (putenv "APPIMAGE" (path->string image))
  (dynamic-wind
    void
    (lambda ()
      (define-values (self staged) (appimage-download-target))
      (check-true (path? self)
                  "APPIMAGE must not leak a string into path->string")
      (check-true (path? staged))
      (when (file-exists? staged) (delete-file staged)))
    (lambda ()
      (when (file-exists? image) (delete-file image))
      (if (and had-appimage (not (equal? had-appimage "")))
          (putenv "APPIMAGE" had-appimage)
          (putenv "APPIMAGE" "")))))

;; Backend-owned install arm: Linux only — the AppImage in-place swap. The
;; flavor gate is platform-symbol (the Racket os value on Linux is 'unix,
;; so comparing system-type with 'linux silently skipped this suite).
(define run-appimage-swap-test?
  (eq? (platform-symbol) 'linux))

(when run-appimage-swap-test?
  (test-case "the AppImage swap replaces the running image and keeps the database"
    (define home (seeded-home))
    (define db-sha (database-sha home))
    (define running-image
      (make-temporary-file "taskly-release-self-~a.AppImage"))
    (call-with-output-file running-image
      #:exists 'truncate
      (lambda (out) (write-bytes (make-bytes 64 1) out)))
    (define new-image-bytes (make-bytes 2048 5))
    (define-values (priv pub) (test-signing-key))
    (define listener (open-loopback))
    (define base (format "http://127.0.0.1:~a" (loopback-port listener)))
    ;; The release feed carries the AppImage as its own signed artifact; the
    ;; installed AppImage flavor selects it by install kind.
    (define manifest
      (update-manifest app-identifier "9.9.9" 7 'stable
                       "2026-10-09T00:00:00Z" "0.0.0" #f #t 100
                       (list (appimage-artifact
                              "https://dl.example/taskly-9.9.9-linux-x86_64.AppImage"
                              new-image-bytes))))
    (define server-thread
      (serve-on! listener
                 (list (cons "update-manifest.json"
                             (wrapped-feed manifest priv))
                       (cons "taskly-9.9.9-linux-x86_64.AppImage"
                             new-image-bytes))))
    (parameterize ([current-taskly-home home])
      ;; read-config hands back a mutable hash; hash-set would reject it on
      ;; the AppImage-only path (the case never ran before this migration).
      (define flavor-config (read-config))
      (hash-set! flavor-config "install-flavor" "appimage")
      (write-config! flavor-config)
      (define had-appimage (getenv "APPIMAGE"))
      (putenv "APPIMAGE" (path->string running-image))
      (reset-update-state!)
      (define checked (check-with-loopback-feed! base pub))
      (check-equal? (hash-ref checked 'status) "available"
                    "the appimage install kind must select the feed artifact")
      (check-equal? (hash-ref checked 'installer) "appimage")
      (start-download!
       (make-temporary-file "taskly-release-appimage-data-~a" 'directory))
      (wait-until (lambda ()
                    (equal? (hash-ref (update-state-snapshot) 'phase)
                            "downloaded"))
                  "the appimage downloaded phase")
      (check-equal? (hash-ref (update-state-snapshot) 'downloadedPath)
                    (path->string running-image)
                    "the swap must replace the running image in place")
      (check-equal? (file->bytes running-image) new-image-bytes)
      (check-true
       (memq 'execute (file-or-directory-permissions running-image 'bits))
       "the replaced image must stay executable")
      (check-equal? (database-sha home) db-sha)
      (check-true (task-survives? home))
      (reset-update-state!)
      (if (and (string? had-appimage) (not (equal? had-appimage "")))
          (putenv "APPIMAGE" had-appimage)
          (putenv "APPIMAGE" "")))
    (kill-thread server-thread)
    (tcp-close listener)))
