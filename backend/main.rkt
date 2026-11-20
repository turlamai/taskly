#lang racket/base

;; Taskly glaze backend (#141) — the single web UI's backend adapter.
;;
;; The Racket engine (racket/taskly) is unchanged: this module loads the
;; production backend, drives it over real in-process RVT1 frames
;; (backend/rvt1.rkt) and exposes every registered RPC 1:1 as a typed
;; glaze route. rivet-schema.json remains the single source of the RPC
;; contract — backend/wire-codec.rkt converts camelCase JSON DTOs to the
;; schema's field-ordered wire values and back, and
;; scripts/check-rpc-surface.py gates this route surface against it.
;;
;; Run:  pnpm --filter @taskly/desktop build   (once)
;;       racket backend/main.rkt
;; Dev:  raco glaze dev  /  TASKLY_TRANSPORT=http for the HTTP adapter.

(require glaze/app        ; run-app, open-app-window, app-quit!, current-app
         glaze/api        ; POST
         glaze/api-macros ; define-api-routes
         glaze/dialogs    ; pick-file/pick-folder/save-file-dialog
         glaze/events     ; make-event-bus, bus-broadcast!
         glaze/shell      ; shell-spawn! (reveal in the system file manager)
         glaze/types      ; GString, GInt64, GBool, GValue, goptional, grecord
         glaze            ; make-tray, make-menu-item, hotkey-register!, …
         glaze/autolaunch ; auto-launch-set! / auto-launch-enabled?
         glaze/global-shortcut ; string->hotkey / hotkey->string
         racket/runtime-path
         racket/system
         racket/path
         racket/port
         json
         "../racket/taskly/config.rkt" ; read-config / config-language (host prefs)
         "../racket/taskly/version.rkt"
         "rvt1.rkt"
         "wire-codec.rkt")

;; The route list schema tooling reads (glaze.rktd points here).
;; start-engine! wires the codec to the in-process RVT1 transport — the
;; app entry and the real-window verifier both call it; schema checks
;; load this module without starting anything.
(provide api start-engine!
         install-host! host-teardown!
         host-open-capture! host-capture-window host-shortcut-registered?
         host-tray-live?)

(define-runtime-path engine-backend "../racket/taskly/backend.rkt")
(define-runtime-path frontend-dist "../apps/desktop/dist")

;; Loading the production backend registers every RPC/Event, exactly as
;; in the embedded runtime. Pure registration — no GUI, no serve thread
;; (schema checks load this module without starting the app).
(void (dynamic-require engine-backend #f))

(define bus (make-event-bus))

;; The engine declares `changed` (Any) but does not emit it today; keep
;; the push path live so a future emitter reaches the UI without a new
;; transport. Payloads must be JSON-serializable for the SSE endpoint.
(set-event-handler!
 (lambda (payload)
   (bus-broadcast! bus 'changed
                   (if (or (hash? payload) (list? payload)
                           (string? payload) (number? payload)
                           (boolean? payload) (eq? payload 'null))
                       payload
                       (format "~s" payload)))))

;; ---- typed RPC surface (1:1 with rivet-schema.json) ----------------------
;; Structured DTOs (records/lists) ride GValue at the transport boundary;
;; their shapes are enforced by the schema-driven codec, and the surface
;; gate keeps names/arity/scalar types aligned with rivet-schema.json.

(define-api-routes api
  ;; health
  [(POST "api/health" #:returns (grecord "Health" "ok" GString "version" GString))
   (health)
   (hasheq 'ok #t 'version app-version)]

  ;; database lifecycle
  [(POST "api/rpc/open_database" #:returns GValue)
   (openDatabase [path GString])
   (rpc/json "open_database" (hasheq 'path path))]
  [(POST "api/rpc/create_database" #:returns GValue)
   (createDatabase [folder GString] [name GString])
   (rpc/json "create_database" (hasheq 'folder folder 'name name))]
  [(POST "api/rpc/migrate_database" #:returns GValue)
   (migrateDatabase [folder GString])
   (rpc/json "migrate_database" (hasheq 'folder folder))]
  [(POST "api/rpc/close_database" #:returns GValue)
   (closeDatabase)
   (rpc/json "close_database" (hasheq))]
  [(POST "api/rpc/default_database" #:returns GString)
   (defaultDatabase)
   (rpc/json "default_database" (hasheq))]

  ;; snapshot / tasks
  [(POST "api/rpc/load_snapshot" #:returns GValue)
   (loadSnapshot [view GString] [listId (goptional GInt64)] [showCompleted GBool])
   (rpc/json "load_snapshot"
             (hasheq 'view view 'listId listId 'showCompleted showCompleted))]
  [(POST "api/rpc/add_task" #:returns GValue)
   (addTask [text GString] [listId (goptional GInt64)]
            [dueDate (goptional GString)] [dueTime (goptional GString)]
            [notes (goptional GString)])
   (rpc/json "add_task"
             (hasheq 'text text 'listId listId 'dueDate dueDate
                     'dueTime dueTime 'notes notes))]
  [(POST "api/rpc/update_task" #:returns GValue)
   (updateTask [task GValue])
   (rpc/json "update_task" (hasheq 'task task))]
  [(POST "api/rpc/update_task_text" #:returns GValue)
   (updateTaskText [id GInt64] [text GString])
   (rpc/json "update_task_text" (hasheq 'id id 'text text))]
  [(POST "api/rpc/set_completed" #:returns GValue)
   (setCompleted [id GInt64] [completed GBool])
   (rpc/json "set_completed" (hasheq 'id id 'completed completed))]
  [(POST "api/rpc/delete_task" #:returns GBool)
   (deleteTask [id GInt64])
   (rpc/json "delete_task" (hasheq 'id id))]
  [(POST "api/rpc/search_tasks" #:returns GValue)
   (searchTasks [keyword GString])
   (rpc/json "search_tasks" (hasheq 'keyword keyword))]

  ;; lists
  [(POST "api/rpc/create_list" #:returns GValue)
   (createList [name GString] [icon (goptional GString)] [color (goptional GInt64)])
   (rpc/json "create_list" (hasheq 'name name 'icon icon 'color color))]
  [(POST "api/rpc/update_list" #:returns GValue)
   (updateList [item GValue])
   (rpc/json "update_list" (hasheq 'item item))]
  [(POST "api/rpc/delete_list" #:returns GBool)
   (deleteList [id GInt64])
   (rpc/json "delete_list" (hasheq 'id id))]

  ;; parsing
  [(POST "api/rpc/parse_due" #:returns GString)
   (parseDue [expression GString])
   (rpc/json "parse_due" (hasheq 'expression expression))]
  [(POST "api/rpc/parse_quick_add" #:returns GValue)
   (parseQuickAdd [text GString])
   (rpc/json "parse_quick_add" (hasheq 'text text))]

  ;; reminders
  [(POST "api/rpc/reminder_decisions" #:returns GValue)
   (reminderDecisions [startup GBool])
   (rpc/json "reminder_decisions" (hasheq 'startup startup))]
  [(POST "api/rpc/acknowledge_reminder" #:returns GBool)
   (acknowledgeReminder [token GString] [phase GString])
   (rpc/json "acknowledge_reminder" (hasheq 'token token 'phase phase))]

  ;; settings
  [(POST "api/rpc/get_settings" #:returns GValue)
   (getSettings)
   (rpc/json "get_settings" (hasheq))]
  [(POST "api/rpc/set_setting" #:returns GValue)
   (setSetting [key GString] [value GString])
   (rpc/json "set_setting" (hasheq 'key key 'value value))]
  [(POST "api/rpc/get_setting" #:returns GString)
   (getSetting [key GString])
   (rpc/json "get_setting" (hasheq 'key key))]

  ;; backup / restore
  [(POST "api/rpc/export_backup" #:returns GInt64)
   (exportBackup [path GString])
   (rpc/json "export_backup" (hasheq 'path path))]
  [(POST "api/rpc/preview_backup" #:returns GValue)
   (previewBackup [path GString])
   (rpc/json "preview_backup" (hasheq 'path path))]
  [(POST "api/rpc/restore_backup" #:returns GValue)
   (restoreBackup [path GString])
   (rpc/json "restore_backup" (hasheq 'path path))]

  ;; updates
  [(POST "api/rpc/check_updates" #:returns GValue)
   (checkUpdates)
   (rpc/json "check_updates" (hasheq))]
  [(POST "api/rpc/start_download" #:returns GValue)
   (startDownload)
   (rpc/json "start_download" (hasheq))]
  [(POST "api/rpc/update_state" #:returns GValue)
   (updateState)
   (rpc/json "update_state" (hasheq))]

  ;; ---- host capabilities (not engine RPCs; outside the surface gate) ----
  ;; Native pickers/reveal for the single web UI. Dialogs block their
  ;; request thread until the user picks; #f means cancelled.
  [(POST "api/host/pick_folder" #:returns GValue)
   (pickFolder [title (goptional GString)])
   (pick-folder #:title (or title #f))]
  [(POST "api/host/pick_file" #:returns GValue)
   (pickFile [title (goptional GString)] [filters GValue])
   (pick-file #:title (or title #f)
              #:filters (or filters '()))]
  [(POST "api/host/save_file" #:returns GValue)
   (saveFile [title (goptional GString)] [defaultName (goptional GString)]
             [filters GValue])
   (save-file-dialog #:title (or title #f)
                     #:default-name (or defaultName #f)
                     #:filters (or filters '()))]
  [(POST "api/host/reveal" #:returns GBool)
   (reveal [path GString])
   (reveal-path path)]

  ;; ---- thin-host capabilities (#141 slice 3) -------------------------
  ;; Global quick-add accelerator: recorded in config `global-quick-add`
  ;; by the settings sheet, registered here with the OS (glaze hotkey).
  [(POST "api/host/shortcut" #:returns GValue)
   (shortcut [accelerator GString])
   (host-apply-shortcut! accelerator)]
  ;; Launch-at-login: the OS entry is the source of truth (no config key).
  [(POST "api/host/autostart" #:returns GValue)
   (autostart)
   (host-autostart-state)]
  [(POST "api/host/autostart_set" #:returns GValue)
   (autostartSet [enabled GBool])
   (host-autostart-set! enabled)]
  ;; Quick-capture popup finished (task added or Esc): push `changed` so
  ;; the main window refetches, then close the popup.
  [(POST "api/host/capture_done" #:returns GBool)
   (captureDone)
   (bus-broadcast! bus 'changed 'null)
   (define wv (unbox capture-wv))
   (when (and wv (not (webview-closed? wv))) (webview-close wv))
   #t])

;; Show a folder in the system file manager (settings → 所在文件夹).
;; Falls back to #f when no opener exists; the UI then shows the path.
(define (reveal-path path)
  (define dir
    (if (directory-exists? path)
        path
        (let-values ([(base name dir?) (split-path path)])
          (if (path? base) (path->string base) path))))
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (case (system-type 'os)
      [(windows) (shell-spawn! "explorer.exe" (list dir)) #t]
      [(macosx) (shell-spawn! "open" (list dir)) #t]
      [else (cond
              [(find-executable-path "xdg-open")
               (shell-spawn! "xdg-open" (list dir)) #t]
              [else #f])])))

;; ---- thin host runtime (#141 slice 3) --------------------------------
;; Tray + global hotkey + quick-capture popup + launch-at-login. The web
;; UI stays the only chrome; these are the OS-deep capabilities the issue
;; keeps as thin-host duties. All callbacks run on foreign threads (tray
;; worker, hotkey message pump), so they re-bind current-app explicitly.

(define main-wv (box #f))
(define capture-wv (box #f))
(define base-url (box #f))
(define host-app (box #f))
(define tray-handle (box #f))
(define registered-hk (box #f))

(define-runtime-path i18n-zh "../shared/i18n/zh.json")
(define-runtime-path i18n-en "../shared/i18n/en.json")
(define-runtime-path icon-ico "../shared/assets/icon.ico")
(define-runtime-path icon-png "../shared/assets/icon-512.png")

;; Host-side labels (tray menu) read the same i18n single source as the
;; web table; language follows config `language` at tray install time.
(define (host-strings)
  (define lang (config-language (read-config)))
  (define path (if (equal? lang "zh") i18n-zh i18n-en))
  (with-handlers ([exn:fail? (lambda (_) (hasheq))])
    (call-with-input-file path (lambda (in) (read-json in)))))

(define (host-t strings key fallback)
  (define v (hash-ref strings key #f))
  (if (string? v) v fallback))

(define (installed-exe?)
  ;; Launch-at-login registers the running executable; under `racket
  ;; backend/main.rkt` (or any script, e.g. the verifier) run-file is the
  ;; interpreter or the source file, which must never become a login item.
  (define p (find-system-path 'run-file))
  (define name (string-downcase (path->string (file-name-from-path p))))
  (and (not (or (path-has-extension? p #".rkt") (path-has-extension? p #".rktd")))
       (not (member name '("racket.exe" "racket")))))

(define (bad-param message)
  (raise (exn:fail:glaze:bad-param message (current-continuation-marks))))

(define (with-host-app thunk)
  (parameterize ([current-app (unbox host-app)]) (thunk)))

;; Show/restore the main window; reopen it when the user closed it while
;; close-to-tray kept the app resident (PRODUCT-SPEC §2 tray contract).
(define (show-main!)
  (with-host-app
   (lambda ()
     (define wv (unbox main-wv))
     (if (and wv (not (webview-closed? wv)))
         (webview-focus! wv)
         (let ([w (open-app-window (unbox base-url)
                                   #:title "Taskly"
                                   #:width 1100
                                   #:height 760
                                   #:on-close main-close!)])
           (set-box! main-wv w))))))

;; Closing the main window: close-to-tray=1 keeps the tray-resident app
;; alive; =0 quits (the engine setting is the single source).
(define (main-close!)
  (set-box! main-wv #f)
  (when (equal? (config-close-to-tray (read-config)) "0")
    (with-host-app (lambda () (app-quit! (unbox host-app))))))

;; The global-hotkey quick-capture popup: a second, small web window on
;; the same page (#capture route), same backend, same engine.
(define (host-open-capture!)
  (with-host-app
   (lambda ()
     (define wv (unbox capture-wv))
     (if (and wv (not (webview-closed? wv)))
         (webview-focus! wv)
         (let ([w (open-app-window (string-append (unbox base-url) "#capture")
                                   #:title "Taskly Quick Add"
                                   #:width 620
                                   #:height 150
                                   #:on-close (lambda () (set-box! capture-wv #f)))])
           (set-box! capture-wv w))))))

(define (host-capture-window) (unbox capture-wv))

(define (host-tray-live?) (and (unbox tray-handle) #t))

;; Register (or clear) the OS accelerator recorded in config. Returns the
;; canonical form so the settings sheet can display what the OS accepted.
(define (host-apply-shortcut! accelerator)
  (hotkey-unregister-all!)
  (set-box! registered-hk #f)
  (cond
    [(or (string=? accelerator "") (string=? accelerator "disabled"))
     (hasheq 'ok #t 'accelerator "")]
    [else
     (define hk (string->hotkey accelerator))
     (unless hk (bad-param (format "accelerator: invalid accelerator ~v" accelerator)))
     (define ok (hotkey-register! hk host-open-capture!))
     (unless ok (bad-param (format "accelerator already in use: ~a" (hotkey->string hk))))
     (set-box! registered-hk hk)
     (hasheq 'ok #t 'accelerator (hotkey->string hk))]))

(define (host-shortcut-registered?)
  (define hk (unbox registered-hk))
  (and hk (hotkey-registered? hk) #t))

(define (autostart-enabled-value)
  (define v (auto-launch-enabled? "Taskly"))
  (if (symbol? v) (symbol->string v) v))

(define (host-autostart-state)
  (hasheq 'enabled (autostart-enabled-value) 'installed (installed-exe?)))

(define (host-autostart-set! enabled)
  (unless (installed-exe?)
    (bad-param "autostart needs an installed build (raco glaze build), not the dev interpreter"))
  (with-handlers ([exn:fail? (lambda (e) (bad-param (exn-message e)))])
    (auto-launch-set! "Taskly" enabled))
  (host-autostart-state))

;; Called from #:on-ready (app entry and verifier): remember the window,
;; install the tray and register the recorded accelerator.
(define (install-host! wv url)
  (set-box! main-wv wv)
  (set-box! base-url url)
  (set-box! host-app (current-app))
  (define strings (host-strings))
  (when (tray-supported?)
    (with-handlers ([exn:fail? (lambda (_) (void))]) ; tray loss never blocks startup
      (set-box! tray-handle
                (make-tray
                 #:icon (if (eq? (system-type 'os) 'windows) icon-ico icon-png)
                 #:tooltip "Taskly"
                 #:menu (list
                         (make-menu-item (host-t strings 'trayShow "Show Taskly")
                                         #:action show-main!)
                         (menu-separator)
                         (make-menu-item (host-t strings 'trayQuit "Quit")
                                         #:action (lambda ()
                                                    (with-host-app
                                                     (lambda () (app-quit! (unbox host-app)))))))
                 #:on-event (lambda (e)
                              (when (memq e '(click left-click)) (show-main!)))))))
  (with-handlers ([exn:fail? (lambda (_) (void))]) ; a taken hotkey never blocks startup
    (host-apply-shortcut! (config-ref (read-config) "global-quick-add" ""))))

(define (host-teardown!)
  (hotkey-unregister-all!)
  (define t (unbox tray-handle))
  (when t (with-handlers ([exn:fail? (lambda (_) (void))]) (tray-close t)))
  (set-box! tray-handle #f))

(define engine-started? #f)

(define (start-engine!)
  (unless engine-started?
    (set-rvt1-call! rvt1-call)
    (start-rvt1! engine-backend)
    (set! engine-started? #t)))

(module+ main
  (start-engine!)

  ;; TASKLY_TRANSPORT=http switches to the explicit dev adapter; the
  ;; production shape is the native GLZ1 carrier (no loopback TCP).
  (define transport
    (or (let ([v (getenv "TASKLY_TRANSPORT")])
          (and (member v '("native" "http")) (string->symbol v)))
        'native))
  (define-values (_kind stop)
    (run-app
     #:public-dir frontend-dist
     #:api api
     #:transport transport
     #:api-token (or (getenv "GLAZE_API_TOKEN") #t)
     #:events bus
     #:title "Taskly"
     #:width 1100
     #:height 760
     #:app-id "taskly"
     #:window-state #t
     ;; Tray-resident: closing the last window does not quit by itself;
     ;; main-close! applies the engine's close-to-tray preference.
     #:quit-on-last-window? #f
     #:on-close main-close!
     #:on-ready (lambda (wv url) (install-host! wv url))
     #:current-version app-version))
  (stop)
  (host-teardown!))