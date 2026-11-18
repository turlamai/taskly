#lang racket/base

;; Backend RPC contract for host preferences (set_setting/get_setting),
;; including the update-check throttle key (shared/spec/UPDATE.md).

(require rackunit
         racket/file
         racket/path
         racket/string
         rivet/backend
         (submod "../taskly/backend.rkt" rpcs)
         "../taskly/config.rkt"
         "../taskly/errors.rkt"
         "../taskly/model.rkt"
         "../taskly/paths.rkt"
         "../taskly/service.rkt")

(define temp-root (make-temporary-file "taskly-backend-test-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (parameterize ([current-taskly-home temp-root])
     ;; get_setting reads raw config; unset keys read as the empty string.
     (check-equal? (get_setting "last-update-check") "")

     ;; set_setting accepts the integer-as-string throttle key and persists
     ;; it through the shared config writer (DATA-FORMAT §7).
     (set_setting "last-update-check" "1728460800")
     (check-equal? (get_setting "last-update-check") "1728460800")
     (check-equal? (config-ref (read-config) "last-update-check") "1728460800")

     ;; Keys are case-insensitive end to end (read + write).
     (set_setting "LAST-Update-Check" "1728461000")
     (check-equal? (get_setting "last-update-check") "1728461000")

     ;; Validation: the throttle must be an integer string; unknown keys are
     ;; rejected as before.
     (check-exn exn:fail? (lambda () (set_setting "last-update-check" "yesterday")))
     (check-exn exn:fail? (lambda () (set_setting "no-such-key" "1")))

     ;; The whitelist regression: last-selected-list-id still works.
     (set_setting "last-selected-list-id" "7")
     (check-equal? (get_setting "last-selected-list-id") "7")

     ;; UPDATE.md auto-check toggle: round-trips as a string enum, rejects
     ;; anything but "0"/"1", and survives the config writer's key list.
     (set_setting "auto-check-updates" "0")
     (check-equal? (get_setting "auto-check-updates") "0")
     (check-equal? (config-ref (read-config) "auto-check-updates") "0")
     (set_setting "auto-check-updates" "1")
     (check-exn exn:fail? (lambda () (set_setting "auto-check-updates" "off")))
     ;; The updater reads this key from disk in a later RPC. Keeping it in
     ;; set_setting's validation table is insufficient if write-config!
     ;; silently drops it during serialization (the Windows MSI 1620 bug).
     (set_setting "install-flavor" "msi")
     (check-equal? (get_setting "install-flavor") "msi")
     (check-equal? (config-ref (read-config) "install-flavor") "msi")
     (check-exn exn:fail?
                (lambda () (set_setting "install-flavor" "exe")))

     ;; open_database remembers the opened file (DATA-FORMAT §7) so hosts
     ;; restart against it — the 0.2.1 OTA regression: manually opened DBs
     ;; were forgotten because nothing ever wrote last-db-path.
     (define remembered-db (build-path temp-root "remembered.db"))
     (close-taskly-service (open-taskly-service remembered-db))
     (open_database (path->string remembered-db))
     (check-equal? (config-ref (read-config) "last-db-path")
                   (path->string (path->complete-path remembered-db)))
     (check-equal? (resolve-database-path)
                   (path->complete-path remembered-db))
     ;; An unregistered database takes its file stem as the display name.
     (check-equal? (config-ref (read-config) "last-db-name") "remembered")

     ;; §2a: opening must never create a replacement for a missing file and
     ;; must refuse a foreign file — the gate's recovery flow depends on it.
     (check-exn
      exn:fail:taskly?
      (lambda ()
        (open_database (path->string (build-path temp-root "absent.db")))))
     (define foreign-file (build-path temp-root "foreign.db"))
     (call-with-output-file foreign-file
       (lambda (out) (displayln "definitely not sqlite" out)))
     (check-exn
      exn:fail:taskly?
      (lambda () (open_database (path->string foreign-file))))

     ;; Exclusive create (PRODUCT-SPEC §2a): the gate flow records the file
     ;; and its entered display name; a second create on the same target is
     ;; rejected before writing anything.
     (define create-dir (build-path temp-root "created"))
     (define created-snapshot (create_database (path->string create-dir) "Gate Home"))
     (check-equal? (length (record-ref created-snapshot 'tasks)) 0)
     (check-equal? (config-ref (read-config) "last-db-path")
                   (path->string (build-path create-dir "taskly.sqlite")))
     (check-equal? (config-ref (read-config) "last-db-name") "Gate Home")
     ;; Reopening the same file keeps the entered display name.
     (open_database (path->string (build-path create-dir "taskly.sqlite")))
     (check-equal? (config-ref (read-config) "last-db-name") "Gate Home")
     (check-exn
      exn:fail:taskly?
      (lambda () (create_database (path->string create-dir) "Again")))
     (check-exn
      exn:fail:taskly?
      (lambda () (create_database (path->string create-dir) "bad/name")))

     ;; §2a default-list + recorded accelerator settings round-trip and
     ;; survive the config writer's key list.
     (set_setting "default-list-id" "3")
     (check-equal? (get_setting "default-list-id") "3")
     (check-equal? (config-ref (read-config) "default-list-id") "3")
     (check-exn exn:fail? (lambda () (set_setting "default-list-id" "soon")))
     (set_setting "global-quick-add" "ctrl+alt+space")
     (check-equal? (get_setting "global-quick-add") "ctrl+alt+space")
     (check-equal? (config-ref (read-config) "global-quick-add") "ctrl+alt+space")

     ;; §2a backup lifecycle: export writes taskly-backup v1 (pretty-printed,
     ;; parseable), preview counts it, restore replaces lists + tasks.
     (define gate-service (open-taskly-service (build-path create-dir "taskly.sqlite")))
     (define gate-list (service-add-list! gate-service "Gate List" #:icon "⭐"))
     (service-add-task! gate-service "exported task"
                        #:list-id (todo-list-id gate-list)
                        #:due-date "2026-09-20")
     (close-taskly-service gate-service)
     (open_database (path->string (build-path create-dir "taskly.sqlite")))
     (define backup-path (build-path temp-root "backup.json"))
     (check-equal? (export_backup (path->string backup-path)) 1)
     (define backup-preview (preview_backup (path->string backup-path)))
     (check-equal? (record-ref backup-preview 'format) "taskly-backup")
     (check-equal? (record-ref backup-preview 'version) 1)
     (check-equal? (record-ref backup-preview 'list-count) 2
                   "the default list plus Gate List")
     (check-equal? (record-ref backup-preview 'task-count) 1)
     (check-true (string-contains? (file->string backup-path) "\n  \"format\": \"taskly-backup\"")
                 "the backup file is 2-space pretty-printed")
     ;; Restore replaces the open database's content in one transaction.
     (restore_backup (path->string backup-path))
     (define restored-service (open-taskly-service (build-path create-dir "taskly.sqlite")))
     (check-equal? (length (service-lists restored-service)) 2)
     (check-equal? (length (service-tasks restored-service)) 1)
     (close-taskly-service restored-service)
     (check-exn
      exn:fail:taskly?
      (lambda () (preview_backup (path->string foreign-file)))
      "a foreign file is rejected as an invalid backup")

     ;; §2a migrate: two RPCs above the core copy primitive; success switches
     ;; the recorded location, failure keeps the source.
     (define migrate-dir (build-path temp-root "migrated-gate"))
     (define migrated-snapshot (migrate_database (path->string migrate-dir)))
     (check-equal? (length (record-ref migrated-snapshot 'tasks)) 1)
     (check-equal? (config-ref (read-config) "last-db-path")
                   (path->string (build-path migrate-dir "taskly.sqlite")))
     (check-true (file-exists? (build-path create-dir "taskly.sqlite"))
                 "the source file stays in place after a successful migrate")
     (check-exn
      exn:fail:taskly?
      (lambda () (migrate_database (path->string create-dir)))
      "an occupied target folder is rejected")

     ;; A legacy underscore key survives a config rewrite (pre-0.x files),
     ;; and the new key wins over it when both exist.
     (define legacy-config (build-path temp-root "legacy-config.ini"))
     (call-with-output-file legacy-config
       (lambda (out)
         (displayln "# Taskly configuration" out)
         (displayln "language = zh" out)
         (displayln "last_db_path = /sync/old.db" out)))
     (define legacy-loaded (read-config legacy-config))
     (check-equal? (resolve-database-path #f legacy-loaded)
                   (path->complete-path "/sync/old.db"))
     (write-config! legacy-loaded legacy-config)
     (check-equal? (config-ref (read-config legacy-config) "last_db_path")
                   "/sync/old.db")))
 (lambda ()
   ;; open_database installs a process-wide service just like the embedded
   ;; host. Close it before removing the disposable profile so Windows does
   ;; not retain an open SQLite handle during test cleanup.
   (close_database)
   (delete-directory/files temp-root)))
