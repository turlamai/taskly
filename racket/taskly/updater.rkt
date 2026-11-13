#lang racket/base

;; Online update support for Taskly, built on rivet/distribution's managed
;; updater — the family pattern (payback/syncpilot): the backend verifies
;; and downloads the signed update artifact; the native host owns
;; installation. The managed instance owns candidate selection, the
;; background worker, progress, the stall/total watchdog, cancellation, and
;; the terminal state; this module supplies the product identity, the feed,
;; the staging path (or the AppImage in-place swap) and maps the snapshot
;; onto the wire shape the UI polls through `update-state` (RVT1 events are
;; thread-local, so a background thread cannot emit them directly).
;;
;; Taskly-specific rules (shared/spec/UPDATE.md): the 4-hour silent-check
;; throttle lives in the hosts via the last-update-check config key — this
;; module only persists the sticky rollout bucket. Downloads land under
;; <taskly-dir>/updates and tasks.db is never touched.

;; Note on crypto factories: rivet/distribution pins the provider set to
;; libcrypto at module load and deliberately avoids crypto/all — factory
;; FFIs load at import time and the gmp factory kills embedded runtimes on
;; hosts without libgmp. This module runs inside the embedded CS runtime,
;; so it must not require crypto/all either (tests may, they are headless).

(require crypto
         (only-in rivet/distribution
                  make-updater
                  updater-check!
                  updater-download!
                  updater-state
                  updater-cancel!
                  updater-wait
                  base64-string->bytes
                  update-candidate-manifest
                  update-manifest-version)
         racket/file
         racket/path
         racket/string
         "config.rkt"
         "paths.rkt"
         "version.rkt")

(provide (all-from-out "version.rkt")
         update-key-id
         update-public-key-b64
         default-update-base-url
         current-update-base-url
         installer-extension
         appimage-download-target
         manifest-url
         destination-path
         update-state-snapshot
         reset-update-state!
         set-update-error!
         perform-check!
         update-install-kind
         start-download!
         cancel-download!
         download-running?
         rollout-bucket)

(define update-key-id "taskly-2026-10")

;; SubjectPublicKeyInfo DER, base64 — the same keypair the macOS host
;; embeds in raw form (UpdateService.swift). The private half lives outside
;; the repository (Sync/Keys backup + the CI secret
;; UPDATE_ED25519_PRIVATE_KEY) and never ships. Rotate by shipping a build
;; that trusts the next key before signing releases exclusively with it.
(define update-public-key-b64
  "MCowBQYDK2VwAyEAlgCdBU0qFDNgamTJBIVX2jjPzehbTmCp3eV5ViubtF0=")

;; Where the updater looks for the signed manifest. The release pipeline
;; pins artifact URLs to the concrete tag; the manifest itself is always
;; fetched from the moving "latest" location. Tests parameterize this at
;; an unreachable local URL instead of touching the network.
(define default-update-base-url
  "https://github.com/turlamai/taskly/releases/latest/download")

(define current-update-base-url (make-parameter #f))

(define maximum-download-bytes (* 800 1024 1024))

;; ---------- platform identity ----------

;; platform-symbol / architecture-symbol live in version.rkt (the CLI's
;; `version` command reports identity without loading this module's
;; crypto/rivet dependencies; they are re-provided above).

(define (installer-extension)
  (case (system-type 'os)
    [(macosx) ".zip"]
    [(windows) ".zip"]
    [else ".tar.gz"]))

(define (manifest-url)
  (string-append
   (string-trim (or (current-update-base-url) default-update-base-url)
                "/" #:right? #t)
   "/update-manifest.json"))

;; ---------- shared update state (UI-visible) ----------

;; phase: idle | checking | downloading | downloaded | error
(define (idle-snapshot)
  (hasheq 'phase "idle"
          'percent 0
          'message #f
          'downloadedPath #f
          'availableVersion #f))

(define update-state (box (idle-snapshot)))
(define updater-box (box #f))
(define download-root-box (box #f))

(define (state-set! key value)
  (set-box! update-state (hash-set (unbox update-state) key value)))

;; Pre-spawn download failures (already running, no candidate) surface
;; through the state instead of an RPC error, so host UIs have a single
;; failure channel. `update-state-snapshot` prefers this box while it holds
;; an error, so a live managed instance cannot hide it.
(define (set-update-error! message)
  (state-set! 'phase "error")
  (state-set! 'message message))

(define (reset-update-state!)
  ;; Dropping an instance while its worker runs would orphan the download;
  ;; land it on the terminal cancelled phase first.
  (define instance (unbox updater-box))
  (when (and instance (equal? (hash-ref (updater-state instance) 'phase)
                              "downloading"))
    (updater-cancel! instance)
    (updater-wait instance 5.0))
  (set-box! updater-box #f)
  (set-box! download-root-box #f)
  (set-box! update-state (idle-snapshot)))

;; The managed phases include transport/selection outcomes the UI treats as
;; idle: `available` carries its signal in availableVersion, `up-to-date`
;; means there is nothing to do, and `cancelled` returns the controls to
;; idle. Anything else passes through unchanged.
(define (managed-state->product state)
  (define phase (hash-ref state 'phase "idle"))
  (define mapped-phase
    (case phase
      [("available" "up-to-date" "cancelled") "idle"]
      [else phase]))
  (define idle? (string=? mapped-phase "idle"))
  (hasheq 'phase mapped-phase
          'percent (if idle? 0 (hash-ref state 'percent 0))
          'message (and (not idle?) (hash-ref state 'message #f))
          'downloadedPath (let ([path (hash-ref state 'downloadedPath #f)])
                            (if path path #f))
          'availableVersion (let ([version (hash-ref state 'availableVersion #f)])
                              (if version version #f))))

(define (update-state-snapshot)
  (define product (unbox update-state))
  (define instance (unbox updater-box))
  (cond
    [(not instance) product]
    ;; A backend-side start failure (for example a second download while
    ;; one is active) outranks the managed snapshot until the next check.
    [(equal? (hash-ref product 'phase "idle") "error") product]
    [else (managed-state->product (updater-state instance))]))

;; ---------- rollout bucket ----------

;; Stable random 0..99 assigned on first check so staged rollouts are
;; sticky per installation. Persisted as an integer-as-string config key
;; (DATA-FORMAT §7); crypto-random-bytes, not `random`: racket/base's PRNG
;; has a fixed seed, which would put every fresh install in the same
;; lockstep bucket.
(define (rollout-bucket)
  (define existing (config-ref (read-config) "rollout-bucket" #f))
  (define parsed (and existing (string->number existing)))
  (if (and parsed (exact-integer? parsed) (<= 0 parsed 99))
      parsed
      (let ([bucket
             (modulo (integer-bytes->integer (crypto-random-bytes 4) #t #t)
                     100)])
        (define config (read-config))
        (hash-set! config "rollout-bucket" (number->string bucket))
        (write-config! config)
        bucket)))

;; ---------- install flavor selection ----------
;; MSI and AppImage are first-class artifacts in the signed manifest. The
;; installed flavor selects the matching signed artifact during check, so
;; the bytes later executed/installed are covered by Ed25519 + SHA-256.

(define (install-flavor)
  (string-downcase (or (config-ref (read-config) "install-flavor") "zip")))

(define (msi-flavor?)
  (and (eq? (platform-symbol) 'windows)
       (equal? (install-flavor) "msi")))

(define (appimage-flavor?)
  (and (eq? (platform-symbol) 'linux)
       (equal? (install-flavor) "appimage")))

(define (update-install-kind)
  (cond
    [(msi-flavor?) 'msi]
    [(appimage-flavor?) 'appimage]
    [else #f]))

;; ---------- download destination ----------

(define (destination-path data-dir candidate [extension (installer-extension)])
  (define version
    (update-manifest-version (update-candidate-manifest candidate)))
  (build-path data-dir
              "updates"
              (string-append app-display-name "-" version extension)))

;; AppImage downloads land next to the running image (same filesystem →
;; atomic rename), verify against the signed manifest, then replace
;; $APPIMAGE; the host re-execs the replaced image on consent.
(define (appimage-download-target)
  ;; $APPIMAGE (set by the AppImage runtime) points at the running image;
  ;; stage the download next to it so the final rename stays on one device.
  (define self-string (getenv "APPIMAGE"))
  (unless (and self-string (non-empty-string? self-string))
    (error 'start-download "APPIMAGE is not set; not running as an AppImage"))
  ;; The public update state carries the downloaded path as a string; keep
  ;; this path end to end or the swap succeeds and the state update throws
  ;; `path->string` after the image has already been replaced (taskly 0.2.6
  ;; audit).
  (define self (string->path self-string))
  ;; Reserve a unique name, then remove the file: a failed verification
  ;; must not strand an empty staging file beside the running image
  ;; (rivet's managed download cleans only its own .partial).
  (define staged
    (make-temporary-file "taskly-update-~a.AppImage"
                         #f
                         (path-only self)))
  (delete-file staged)
  (values self staged))

(define (install-appimage! verified self)
  (unless (eq? (system-type 'os) 'windows)
    (file-or-directory-permissions verified #o755))
  (rename-file-or-directory verified self #t)
  self)

;; ---------- managed updater ----------

;; One construction site for the product identity, feed policy, staging
;; path and in-place install step. The managed instance owns the worker,
;; watchdog, cancellation and terminal state.
(define (make-taskly-updater)
  ;; Set by the destination callback for an AppImage install and consumed
  ;; by the after-download hook in the same instance.
  (define appimage-self-box (box #f))
  (make-updater
   #:application-id app-identifier
   #:current-version app-version
   #:channel app-channel
   #:platform (platform-symbol)
   #:architecture (architecture-symbol)
   #:install-kind (update-install-kind)
   ;; The feed's artifacts carry no component discriminator (rivet #271).
   #:component #f
   ;; DER bytes: the managed updater decodes them lazily during the check.
   #:public-key (base64-string->bytes update-public-key-b64)
   #:key-id update-key-id
   #:manifest-url (manifest-url)
   #:data-directory (taskly-directory)
   #:destination
   (lambda (candidate)
     (cond
       [(appimage-flavor?)
        (define-values (self staged) (appimage-download-target))
        (set-box! appimage-self-box self)
        staged]
       [(msi-flavor?) (destination-path (download-root) candidate ".msi")]
       [else (destination-path (download-root) candidate)]))
   #:after-download
   (lambda (verified candidate)
     (define self (unbox appimage-self-box))
     (if self
         (install-appimage! verified self)
         verified))
   #:rollout-bucket (rollout-bucket)
   #:maximum-download-bytes maximum-download-bytes))

(define (download-root)
  (or (unbox download-root-box) (taskly-directory)))

;; ---------- check ----------

;; Returns the managed wire result (status/currentVersion/availableVersion/
;; build/publishedAt/installer/sizeBytes/url); the backend maps it onto the
;; typed UpdateCheck record. Throttling is the host's job (UPDATE.md).
(define (perform-check!)
  (reset-update-state!)
  (with-handlers
      ([exn:fail?
        (lambda (e)
          (state-set! 'phase "error")
          (state-set! 'message (exn-message e))
          (hasheq 'status "error" 'message (exn-message e)))])
    (define instance (make-taskly-updater))
    (set-box! updater-box instance)
    (updater-check! instance)))

;; ---------- download ----------

(define (download-running?)
  (define instance (unbox updater-box))
  (and instance
       (equal? (hash-ref (updater-state instance) 'phase) "downloading")))

(define (start-download! data-dir)
  (define instance (unbox updater-box))
  (unless instance
    (error 'start-download! "no update is available; run a check first"))
  (set-box! download-root-box data-dir)
  (updater-download! instance))

;; The backend's start_download RPC is a start/cancel toggle. Wait for the
;; terminal phase so the host's next update_state poll cannot observe a
;; mid-flight percent (the managed phase maps cancelled → idle).
(define (cancel-download!)
  (define instance (unbox updater-box))
  (cond
    [(and instance (download-running?))
     (updater-cancel! instance)
     (updater-wait instance 5.0)
     #t]
    [else #f]))
