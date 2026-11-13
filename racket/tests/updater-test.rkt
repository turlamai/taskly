#lang racket/base

;; Updater tests: platform mapping, manifest URL construction, the sticky
;; rollout bucket, the product phase mapping over the managed state
;; machine, cancellation, and the offline trust chain — craft a manifest,
;; sign it with a throwaway Ed25519 key, verify it, and select updates the
;; same way the live checker does. (fetch-update-manifest itself only
;; accepts HTTPS, so a live network check is exercised in production and
;; the error path runs here against a closed local port; selected checks
;; inject the already-verified manifest through the managed updater's
;; test-support parameter.)

(require crypto
         crypto/all
         rackunit
         ;; Whitelist instead of the full module: updater.rkt re-exports the
         ;; taskly release-target vocabulary, which rivet also centralizes;
         ;; the explicit list makes the dependency visible.
         (only-in rivet/distribution
                  write-signed-manifest
                  verify-signed-manifest
                  update-manifest
                  update-artifact
                  update-artifact-installer
                  update-candidate
                  update-candidate-artifact
                  update-manifest-artifacts
                  updater-config
                  select-update
                  fetch-update-manifest
                  update-manifest-version
                  sha256-file/hex)
         ;; The managed updater exposes its transport parameters only to
         ;; tests: this suite checks signed selection without an HTTPS
         ;; server, then runs the real download worker against loopback.
         (submod (lib "rivet/distribution/managed-updater.rkt") test-support)
         racket/file
         racket/list
         racket/path
         racket/tcp
         "../taskly/config.rkt"
         "../taskly/paths.rkt"
         "../taskly/updater.rkt")

(use-all-factories!)

;; Poll until the predicate holds or the timeout lapses (rackunit fails).
(define (wait-until ready? who [timeout-ms 10000])
  (let loop ([deadline (+ (current-inexact-milliseconds) timeout-ms)])
    (cond
      [(ready?) (void)]
      [(> (current-inexact-milliseconds) deadline)
       (fail (string-append "timed out waiting for " who))]
      [else (sleep 0.05) (loop deadline)])))

(define (temp-home prefix)
  (make-temporary-file prefix 'directory))

;; A managed check whose manifest was already verified (or crafted by a
;; test): the transport parameter is captured when perform-check! builds
;; the instance.
(define (check-with-manifest! manifest)
  (parameterize ([current-managed-fetch-manifest
                  (lambda (_url _key
                          #:key-id [_key-id #f]
                          #:trusted-keys [_trusted-keys '()]
                          #:maximum-bytes [_maximum-bytes (* 1024 1024)])
                    manifest)])
    (perform-check!)))

(define (test-artifact url installer [size 10])
  (update-artifact (platform-symbol) (architecture-symbol)
                   url (make-string 64 #\a) size installer '()
                   ;; rivet #271: component #f = the plain whole-app artifact.
                   #f))

(define (test-manifest version artifacts)
  (update-manifest app-identifier version 7 'stable
                   "2026-10-09T00:00:00Z" "0.0.0" #f #t 100 artifacts))

(test-case "platform symbols match rivet release manifests"
  (case (system-type 'os)
    [(macosx) (check-equal? (platform-symbol) 'macos)]
    [(windows) (check-equal? (platform-symbol) 'windows)]
    [else (check-equal? (platform-symbol) 'linux)])
  (check-not-false (memq (architecture-symbol) '(arm64 x64))))

(test-case "installer extension follows platform"
  (check-not-false
   (member (installer-extension) '(".zip" ".tar.gz"))
   "known installer extension"))

(test-case "manifest url joins base and file name"
  (check-equal? (manifest-url)
                (string-append default-update-base-url "/update-manifest.json"))
  (check-equal?
   (parameterize ([current-update-base-url "https://dl.example/taskly/"])
     (manifest-url))
   "https://dl.example/taskly/update-manifest.json")
  (check-equal?
   (parameterize ([current-update-base-url "https://dl.example/taskly"])
     (manifest-url))
   "https://dl.example/taskly/update-manifest.json"))

(test-case "rollout bucket is sticky and persists to config.ini"
  (parameterize ([current-taskly-home (temp-home "taskly-updater-home-~a")])
    (check-true (exact-integer? (rollout-bucket)))
    (define first (rollout-bucket))
    (check-true (<= 0 first 99))
    ;; a second read returns the persisted bucket, not a fresh draw
    (check-equal? (rollout-bucket) first)
    (check-equal?
     (config-ref (read-config) "rollout-bucket" #f)
     (number->string first))))

(test-case "check against an unreachable feed reports error state"
  (parameterize ([current-update-base-url "https://127.0.0.1:9/taskly"]
                 [current-taskly-home (temp-home "taskly-updater-offline-~a")])
    (reset-update-state!)
    (define result (perform-check!))
    (check-equal? (hash-ref result 'status) "error")
    (check-equal? (hash-ref (update-state-snapshot) 'phase) "error")
    (check-true (string? (hash-ref (update-state-snapshot) 'message)))))

(test-case "managed check maps onto the wire phase vocabulary"
  (parameterize ([current-taskly-home (temp-home "taskly-updater-map-~a")])
    (reset-update-state!)
    (define available
      (check-with-manifest!
       (test-manifest "9.9.9" (list (test-artifact "https://dl.example/taskly.zip" 'zip)))))
    (check-equal? (hash-ref available 'status) "available")
    (check-equal? (hash-ref available 'availableVersion) "9.9.9")
    ;; The product UI treats "available" as idle; the version carries the
    ;; signal, exactly as before the managed migration.
    (check-equal? (hash-ref (update-state-snapshot) 'phase) "idle")
    (check-equal? (hash-ref (update-state-snapshot) 'availableVersion) "9.9.9")
    (check-equal? (hash-ref (update-state-snapshot) 'percent) 0)

    ;; An older feed is up-to-date and idles with no offered version.
    (reset-update-state!)
    (define stale (test-manifest "0.0.1" (list (test-artifact "https://dl.example/old.zip" 'zip))))
    (define up-to-date (check-with-manifest! stale))
    (check-equal? (hash-ref up-to-date 'status) "up-to-date")
    (check-equal? (hash-ref (update-state-snapshot) 'phase) "idle")
    (check-false (hash-ref (update-state-snapshot) 'availableVersion))

    ;; A backend-side start failure outranks the managed snapshot until the
    ;; next check clears it.
    (check-with-manifest!
     (test-manifest "9.9.9" (list (test-artifact "https://dl.example/taskly.zip" 'zip))))
    (set-update-error! "download already running")
    (check-equal? (hash-ref (update-state-snapshot) 'phase) "error")
    (check-equal? (hash-ref (update-state-snapshot) 'message)
                  "download already running")
    (reset-update-state!)))

(test-case "managed download publishes progress and the final path"
  (define data-dir (make-temporary-file "taskly-updater-progress-~a" 'directory))
  (define (fake-download _config _candidate destination
                         #:on-progress on-progress
                         #:progress-every [_progress-every #f])
    (for ([percent (in-list '(0 40 100))])
      (on-progress percent))
    (make-parent-directory* destination)
    (call-with-output-file destination
      #:exists 'truncate/replace
      (lambda (out) (display "verified artifact" out)))
    destination)
  (parameterize ([current-taskly-home (temp-home "taskly-updater-progress-home-~a")]
                 [current-managed-fetch-manifest
                  (lambda (_url _key
                          #:key-id [_key-id #f]
                          #:trusted-keys [_trusted-keys '()]
                          #:maximum-bytes [_maximum-bytes (* 1024 1024)])
                    (test-manifest
                     "9.9.9"
                     (list (test-artifact "https://dl.example/taskly.zip" 'zip))))]
                 [current-managed-download fake-download])
    (reset-update-state!)
    (check-equal? (hash-ref (perform-check!) 'status) "available")
    (start-download! data-dir)
    (wait-until (lambda ()
                  (equal? (hash-ref (update-state-snapshot) 'phase)
                          "downloaded"))
                "the downloaded phase")
    (define snapshot (update-state-snapshot))
    (check-equal? (hash-ref snapshot 'percent) 100)
    (check-false (hash-ref snapshot 'message))
    (define downloaded (hash-ref snapshot 'downloadedPath))
    (check-true (and downloaded (file-exists? downloaded)))
    (check-equal? (file->string downloaded) "verified artifact")
    (check-false (download-running?))
    (reset-update-state!)))

(test-case "signed manifest verifies and selects updates"
  ;; throwaway keypair: same DER formats the release pipeline uses
  (define priv (generate-private-key 'eddsa '((curve ed25519))))
  (define priv-der (pk-key->datum priv 'OneAsymmetricKey))
  (define priv-path (make-temporary-file "taskly-test-key-~a.der"))
  (with-output-to-file priv-path
    #:exists 'truncate
    (lambda () (write-bytes priv-der)))
  (define pub (datum->pk-key (pk-key->datum priv 'rkt-public) 'rkt-public))
  (define artifact-file (make-temporary-file "taskly-artifact-~a.zip"))
  (call-with-output-file artifact-file
    #:exists 'truncate
    (lambda (out) (write-bytes (make-bytes 128 3) out)))
  (define manifest
    (update-manifest
     app-identifier "9.9.9" 7 'stable
     "2026-10-09T00:00:00Z" "0.0.0" #f #t 100
     (list (update-artifact (platform-symbol) (architecture-symbol)
                            "https://dl.example/taskly/taskly-9.9.9.zip"
                            (sha256-file/hex artifact-file)
                            (file-size artifact-file)
                            'zip '()
                            ;; rivet #271: component #f = the plain whole-app
                            ;; artifact.
                            #f))))
  ;; write-signed-manifest refuses malformed manifests before signing
  (define wrapped (open-output-bytes))
  (write-signed-manifest manifest priv "taskly-test" wrapped)
  (define verified
    (verify-signed-manifest (open-input-bytes (get-output-bytes wrapped))
                            pub
                            #:key-id "taskly-test"))
  (check-equal? (update-manifest-version verified) "9.9.9")
  ;; a different key-id fails closed
  (check-exn exn:fail?
             (lambda ()
               (verify-signed-manifest
                (open-input-bytes (get-output-bytes wrapped))
                pub
                #:key-id "some-other-key")))
  ;; the manifest transport itself refuses plain http (the production feed
  ;; is HTTPS-only); the managed check's default fetch is this function.
  (check-exn #rx"HTTPS"
             (lambda ()
               (fetch-update-manifest "http://127.0.0.1:1/update-manifest.json"
                                      pub #:key-id "taskly-test")))
  (delete-file priv-path)
  (delete-file artifact-file))

(test-case "signed manifest selects the requested installable artifact"
  (define manifest
    (update-manifest
     app-identifier "9.9.9" 7 'stable
     "2026-10-09T00:00:00Z" "0.0.0" #f #t 100
     (list
      (update-artifact 'windows 'x64
                       "https://dl.example/taskly/taskly-9.9.9-windows-x64.zip"
                       (make-string 64 #\a) 10 'zip '() #f)
      (update-artifact 'windows 'x64
                       "https://dl.example/taskly/taskly-9.9.9-windows-x64.msi"
                       (make-string 64 #\b) 20 'msi '() #f)
      (update-artifact 'linux 'x64
                       "https://dl.example/taskly/taskly-9.9.9-linux-x64.tar.gz"
                       (make-string 64 #\c) 30 'targz '() #f)
      (update-artifact 'linux 'x64
                       "https://dl.example/taskly/taskly-9.9.9-linux-x86_64.AppImage"
                       (make-string 64 #\d) 40 'appimage '() #f))))
  (define common
    (updater-config app-identifier "0.0.1" 'stable
                    'windows 'x64 #f #f 0 (* 1024 1024) #f))
  (check-equal?
   (update-artifact-installer
    (update-candidate-artifact
     (select-update common manifest #:install-kind 'msi)))
   'msi)
  (check-equal?
   (update-artifact-installer
    (update-candidate-artifact
     (select-update (struct-copy updater-config common [platform 'linux])
                    manifest
                    #:install-kind 'appimage)))
   'appimage))

(test-case "embedded release identity is coherent"
  (check-equal? app-identifier "app.taskly.Taskly")
  (check-equal? app-channel 'stable)
  (check-equal? update-key-id "taskly-2026-10")
  (check-true (string? app-version)))

(test-case "user cancellation stops the worker and permits retry"
  (define data-dir (make-temporary-file "taskly-updater-cancel-data-~a" 'directory))
  (define listener (tcp-listen 0 16 #f))
  (define-values (_listen-host cancel-port _peer-host _peer-port)
    (tcp-addresses listener #t))
  ;; Two connections: the first download is cancelled mid-copy, the retry
  ;; reaches the same stalling server again.
  (define stall-server
    (thread
     (lambda ()
       (for ([attempt (in-range 2)])
         (define-values (cin cout) (tcp-accept listener))
         (let drain ()
           (define line (read-line cin 'return-linefeed))
           (unless (or (eof-object? line) (equal? line "")) (drain)))
         (display "HTTP/1.1 200 OK\r\nContent-Length: 1000\r\nConnection: close\r\n\r\n" cout)
         (write-bytes (make-bytes 10 5) cout)
         (flush-output cout)
         (read-byte cin)
         (close-input-port cin)
         (close-output-port cout)))))
  (define manifest
    (test-manifest
     "9.9.9"
     (list (update-artifact (platform-symbol) (architecture-symbol)
                            (format "http://127.0.0.1:~a/taskly-9.9.9~a"
                                    cancel-port (installer-extension))
                            (make-string 64 #\0)
                            1000
                            'zip '() #f))))
  (define temporary
    (path-add-extension
     (destination-path
      data-dir
      (update-candidate manifest (first (update-manifest-artifacts manifest))))
     #".partial"))
  (parameterize ([current-taskly-home (temp-home "taskly-updater-cancel-home-~a")])
    (reset-update-state!)
    (check-with-manifest! manifest)
    (start-download! data-dir)
    (wait-until (lambda () (file-exists? temporary)) "first partial")
    (check-true (cancel-download!))
    (check-equal? (hash-ref (update-state-snapshot) 'phase) "idle")
    (check-false (hash-ref (update-state-snapshot) 'message))
    (check-false (file-exists? temporary))

    ;; The authenticated candidate remains selected, so retry needs no
    ;; second check.
    (check-not-exn (lambda () (start-download! data-dir)))
    (wait-until (lambda () (file-exists? temporary)) "retry partial")
    (check-true (cancel-download!))
    (check-equal? (hash-ref (update-state-snapshot) 'phase) "idle")
    (check-false (file-exists? temporary))
    (reset-update-state!))
  (kill-thread stall-server)
  (tcp-close listener))
