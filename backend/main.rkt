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

(require glaze/app        ; run-app
         glaze/api        ; POST
         glaze/api-macros ; define-api-routes
         glaze/events     ; make-event-bus, bus-broadcast!
         glaze/types      ; GString, GInt64, GBool, GValue, goptional, grecord
         racket/runtime-path
         "../racket/taskly/version.rkt"
         "rvt1.rkt"
         "wire-codec.rkt")

;; The route list schema tooling reads (glaze.rktd points here).
;; start-engine! wires the codec to the in-process RVT1 transport — the
;; app entry and the real-window verifier both call it; schema checks
;; load this module without starting anything.
(provide api start-engine!)

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
   (rpc/json "update_state" (hasheq))])

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
   #:current-version app-version))