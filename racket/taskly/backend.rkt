#lang racket/base

(require rivet/backend
         json
         racket/date
         racket/file
         racket/format
         racket/path
         racket/string
         "clock.rkt"
         "config.rkt"
         "date-parser.rkt"
         "db.rkt"
         "errors.rkt"
         "model.rkt"
         "paths.rkt"
         "rivet-schema.rkt"
         "service.rkt"
         "updater.rkt"
         "validation.rkt")

(provide start
         start-stdio)

;; Rivet's diagnostic sink defaults to current-error-port. A Windows
;; GUI-subsystem process has no console, and the embedded Chez runtime
;; lazily allocates one on the first stderr write — the black console
;; window users saw open before the app window, streaming RVT1 protocol
;; records (on mac/Linux stderr lands in a terminal or /dev/null, so it
;; never showed there). Diagnostics keep their value as JSONL appended to
;; ~/.taskly/diagnostics.log instead; stderr is never touched, so no
;; console is ever allocated. Rivet already swallows sink exceptions, so
;; an unwritable path drops records rather than failing the backend.
(define diagnostics-port (box #f))
(define diagnostics-lock (make-semaphore 1))

(define (diagnostics-log-path)
  (build-path (taskly-directory) "diagnostics.log"))

(define (diagnostic-timestamp)
  ;; Local ISO-8601 (no zone suffix): machine-sortable, human-readable.
  (define d (seconds->date (current-seconds) #f))
  (format "~a-~a-~aT~a:~a:~a"
          (date-year d)
          (~r (date-month d) #:min-width 2 #:pad-string "0")
          (~r (date-day d) #:min-width 2 #:pad-string "0")
          (~r (date-hour d) #:min-width 2 #:pad-string "0")
          (~r (date-minute d) #:min-width 2 #:pad-string "0")
          (~r (date-second d) #:min-width 2 #:pad-string "0")))

(define (taskly-diagnostic-sink record)
  (call-with-semaphore
   diagnostics-lock
   (lambda ()
     (define out
       (or (unbox diagnostics-port)
           (let ([port
                  (begin
                    ;; The directory may not exist yet during the very first
                    ;; handshake (open_database creates it right after).
                    (with-handlers ([exn:fail? void])
                      (make-directory* (taskly-directory)))
                    (open-output-file (diagnostics-log-path)
                                      #:exists 'append))])
             (set-box! diagnostics-port port)
             port)))
     (write-json (hash-set record 'ts (diagnostic-timestamp)) out)
     (newline out)
     (flush-output out))))

;; Module top level: runs on the boot thread that later invokes `start`,
;; so serve-fds picks this sink up as its default.
(current-rivet-diagnostic-sink taskly-diagnostic-sink)

(define current-service (box #f))
(define-event changed)

(define (require-service)
  (or (unbox current-service)
      (error 'taskly "database is not open")))

(define (publish! service)
  (changed (snapshot->dto service)))

;; PRODUCT-SPEC §2a: opening must never create a replacement for a missing
;; file nor adopt a foreign database — the gate's recovery flow depends on
;; both. The CLI keeps its own open-or-create semantics (CLI-SPEC).
(define-rpc (open_database [path : String] : Snapshot)
  (define complete (path->complete-path path))
  (unless (file-exists? complete)
    (raise-taskly 'database 4 (format "database file not found: ~a" complete)))
  (unless (taskly-database-file? complete)
    (raise-taskly 'database 4 (format "not a taskly database: ~a" complete)))
  (define previous (unbox current-service))
  (when previous (close-taskly-service previous))
  (define service (open-taskly-service complete))
  (set-box! current-service service)
  ;; Remember the opened database (DATA-FORMAT §7): a manually opened file
  ;; must survive relaunch. A user-entered display name survives reopening
  ;; the same file; an unregistered database takes its file stem.
  (define config (read-config))
  (define previous-path (config-ref config "last-db-path"))
  (define recorded-name (config-last-db-name config))
  (define keep-name?
    (and previous-path
         (not (string=? previous-path ""))
         (equal? (path->complete-path previous-path) complete)
         (not (string=? recorded-name ""))))
  (hash-set! config "last-db-path" (path->string complete))
  (hash-set! config "last-db-name"
             (if keep-name?
                 recorded-name
                 (path->string (path-replace-extension
                                (file-name-from-path complete) ""))))
  (write-config! config)
  (snapshot->dto service))

;; Exclusive create (PRODUCT-SPEC §2a / DATA-FORMAT §7): an explicitly chosen
;; folder + entered name → <folder>/taskly.sqlite. Existing targets are
;; rejected before anything is written; a failure leaves no file behind.
(define-rpc (create_database [folder : String] [name : String] : Snapshot)
  (define clean-name (validate-database-name! name))
  (when (string=? (string-trim folder) "")
    (raise-taskly 'validation 2 "Please choose a folder first."))
  (define target
    (build-path (path->complete-path (string-trim folder)) "taskly.sqlite"))
  (define db (create-taskly-db target))
  (close-taskly-db db)
  (define previous (unbox current-service))
  (when previous (close-taskly-service previous))
  (define service (open-taskly-service target))
  (set-box! current-service service)
  (define config (read-config))
  (hash-set! config "last-db-path" (path->string (path->complete-path target)))
  (hash-set! config "last-db-name" clean-name)
  (write-config! config)
  (snapshot->dto service))

;; Two-step migrate (PRODUCT-SPEC §2a): the caller has already confirmed
;; from → to. All-or-nothing — the source stays open and untouched on any
;; failure; success switches the recorded location. The source file remains
;; in place (user-managed data).
(define-rpc (migrate_database [folder : String] : Snapshot)
  (define service (require-service))
  (define source-path (taskly-db-path (taskly-service-db service)))
  (when (string=? (string-trim folder) "")
    (raise-taskly 'validation 2 "Please choose a target folder first."))
  (define target
    (build-path (path->complete-path (string-trim folder)) "taskly.sqlite"))
  (when (equal? source-path (path->complete-path target))
    (raise-taskly 'validation 2 "the target equals the current location"))
  (migrate-database-file! (taskly-service-db service) target)
  ;; Switch the open service to the new location; if the reopen somehow
  ;; fails after a successful copy, fall back to the intact source.
  (define new-service
    (with-handlers
        ([exn:fail?
          (lambda (e)
            (set-box! current-service (open-taskly-service source-path))
            (raise-taskly 'database 4
                          (format "migration to ~a failed: ~a"
                                  (path->string target) (exn-message e))))])
      (define opened (open-taskly-service target))
      (close-taskly-service service)
      (set-box! current-service opened)
      opened))
  (define config (read-config))
  (hash-set! config "last-db-path" (path->string target))
  (write-config! config)
  (snapshot->dto new-service))

;; ------------------------------------------------------------ backup JSON
;; DATA-FORMAT §9: `taskly-backup` v1 — the export/restore exchange format
;; for the settings 数据 group (PRODUCT-SPEC §2a). Pretty-printed with two
;; spaces so the file reads like the prototype's JSON.stringify(..., null, 2).

(define (write-json-pretty v out [depth 0])
  (define pad (make-string (* 2 depth) #\space))
  (cond
    [(hash? v)
     (if (zero? (hash-count v))
         (display "{}" out)
         (let ([keys (hash-keys v)])
           (display "{\n" out)
           (for ([key (in-list keys)] [i (in-range (length keys))])
             (display (make-string (* 2 (add1 depth)) #\space) out)
             ;; A symbol is a legal hash key for write-json but not a
             ;; standalone JSON value — stringify before writing.
             (write-json (if (symbol? key) (symbol->string key) key) out)
             (display ": " out)
             (write-json-pretty (hash-ref v key) out (add1 depth))
             (unless (= i (sub1 (length keys))) (display "," out))
             (newline out))
           (display pad out)
           (display "}" out)))]
    [(list? v)
     (if (null? v)
         (display "[]" out)
         (begin
           (display "[\n" out)
           (for ([item (in-list v)] [i (in-range (length v))])
             (display (make-string (* 2 (add1 depth)) #\space) out)
             (write-json-pretty item out (add1 depth))
             (unless (= i (sub1 (length v))) (display "," out))
             (newline out))
           (display pad out)
           (display "]" out)))]
    [else (write-json v out)]))

(define (list->backup-json item)
  ;; write-json maps #f to JSON null (DATA-FORMAT §9 optional icon/color);
  ;; a raw void would not be a valid jsexpr.
  (hasheq 'id (todo-list-id item)
          'name (todo-list-name item)
          'icon (or (todo-list-icon item) #f)
          'color (or (todo-list-color item) #f)))

(define (task->backup-json task)
  (hasheq 'listId (task-item-list-id task)
          'text (task-item-text task)
          'completed (task-item-completed task)
          'dueDate (or (task-item-due-date task) "")
          'dueTime (or (task-item-due-time task) "")
          'notes (or (task-item-notes task) "")
          'createdAt (task-item-created-at task)
          'priority (or (task-item-priority task) 0)
          'tags (or (task-item-tags task) (list))
          'subtasks (for/list ([item (in-list (or (task-item-subtasks task) (list)))])
                      (hasheq 'text (subtask-text item) 'done (subtask-done item)))
          'url (or (task-item-url task) "")))

(define max-backup-bytes (* 5 1024 1024))

(define (jsexpr->opt-string v)
  (cond [(string? v) v]
        [(void? v) #f]
        [else #f]))

(define (jsexpr->opt-int v)
  (cond [(exact-integer? v) v]
        [else #f]))

(define (backup-shape-error detail)
  (raise-taskly 'validation 2 (format "invalid backup file: ~a" detail)))

(define (parse-backup-tasks raw-list-ids raw)
  (unless (list? raw) (backup-shape-error "tasks must be an array"))
  (when (> (length raw) max-backup-tasks)
    (raise-taskly 'validation 2
                  (format "backup holds more than ~a tasks" max-backup-tasks)))
  (for/list ([entry (in-list raw)])
    (unless (hash? entry) (backup-shape-error "each task must be an object"))
    (define list-id (hash-ref entry 'listId (void)))
    (unless (exact-integer? list-id) (backup-shape-error "task listId must be an integer"))
    (unless (member list-id raw-list-ids) (backup-shape-error "task listId has no matching list"))
    (define text (hash-ref entry 'text (void)))
    (unless (and (string? text) (not (string=? (string-trim text) "")))
      (backup-shape-error "task text must be non-empty text"))
    (when (> (string-length text) max-task-text-length)
      (backup-shape-error "task text is too long"))
    (define completed (hash-ref entry 'completed (void)))
    (unless (boolean? completed) (backup-shape-error "task completed must be a boolean"))
    (define due-date (jsexpr->opt-string (hash-ref entry 'dueDate (void))))
    (define due-time (jsexpr->opt-string (hash-ref entry 'dueTime (void))))
    (define notes (jsexpr->opt-string (hash-ref entry 'notes (void))))
    (define created-at (hash-ref entry 'createdAt (void)))
    (unless (and (string? created-at) (not (string=? created-at "")))
      (backup-shape-error "task createdAt must be non-empty text"))
    (define priority (hash-ref entry 'priority (void)))
    (unless (and (exact-integer? priority) (<= 0 priority 3))
      (backup-shape-error "task priority must be 0..3"))
    (define tags
      (for/list ([tag (in-list
                       (let ([v (hash-ref entry 'tags (void))])
                         (unless (list? v) (backup-shape-error "task tags must be an array"))
                         v))])
        (unless (and (string? tag) (not (string=? (string-trim tag) "")))
          (backup-shape-error "task tags must be non-empty text"))
        (when (> (string-length tag) max-tag-length)
          (backup-shape-error "task tags are too long"))
        (string-trim tag)))
    (define subtasks
      (for/list ([sub (in-list
                       (let ([v (hash-ref entry 'subtasks (void))])
                         (unless (list? v) (backup-shape-error "task subtasks must be an array"))
                         v))])
        (unless (hash? sub) (backup-shape-error "each subtask must be an object"))
        (define sub-text (hash-ref sub 'text (void)))
        (define sub-done (hash-ref sub 'done (void)))
        (unless (and (string? sub-text) (not (string=? (string-trim sub-text) ""))
                     (boolean? sub-done))
          (backup-shape-error "subtask text/done is incomplete"))
        (when (> (string-length sub-text) max-subtask-text-length)
          (backup-shape-error "subtask text is too long"))
        (subtask (string-trim sub-text) sub-done)))
    (define url (jsexpr->opt-string (hash-ref entry 'url (void))))
    (when (and url (> (string-length url) max-url-length))
      (backup-shape-error "task url is too long"))
    ;; list-id is re-based to the 0-based list order for db-restore-backup!
    (task-item 0
               (- (length raw-list-ids) (length (member list-id raw-list-ids)))
               (string-trim text)
               (and due-date (not (string=? due-date "")) due-date)
               (and due-time (not (string=? due-time "")) due-time)
               completed
               created-at
               (and notes (not (string=? notes "")) notes)
               #f
               priority
               tags
               subtasks
               (and url (not (string=? url "")) url))))

(define (parse-backup-file path)
  (define complete (path->complete-path path))
  (unless (file-exists? complete)
    (raise-taskly 'validation 2 (format "backup file not found: ~a" complete)))
  (define size (file-size complete))
  (when (> size max-backup-bytes)
    (raise-taskly 'validation 2 "backup file is larger than 5 MB"))
  (define data
    (with-handlers
        ([exn:fail? (lambda (_) (backup-shape-error "the file is not valid JSON"))])
      (read-json (open-input-string (file->string complete)))))
  (unless (hash? data) (backup-shape-error "the backup must be a JSON object"))
  (unless (equal? (hash-ref data 'format (void)) "taskly-backup")
    (backup-shape-error "format must be taskly-backup"))
  (unless (equal? (hash-ref data 'version (void)) 1)
    (backup-shape-error "version must be 1"))
  (define raw-lists (hash-ref data 'lists (void)))
  (unless (list? raw-lists) (backup-shape-error "lists must be an array"))
  (define list-entries
    (for/list ([entry (in-list raw-lists)])
      (unless (hash? entry) (backup-shape-error "each list must be an object"))
      (define name (hash-ref entry 'name (void)))
      (unless (and (string? name) (not (string=? (string-trim name) "")))
        (backup-shape-error "list name must be non-empty text"))
      (when (> (string-length name) max-list-name-length)
        (backup-shape-error "list name is too long"))
      (list (string-trim name)
            (jsexpr->opt-string (hash-ref entry 'icon (void)))
            (jsexpr->opt-int (hash-ref entry 'color (void))))))
  (define list-ids
    (for/list ([entry (in-list raw-lists)])
      (unless (hash? entry) (backup-shape-error "each list must be an object"))
      (define id (hash-ref entry 'id (void)))
      (unless (exact-integer? id) (backup-shape-error "list id must be an integer"))
      id))
  (define tasks (parse-backup-tasks list-ids (hash-ref data 'tasks (void))))
  (values list-entries tasks (length list-entries) (length tasks)))

;; Writes the selected database's lists + tasks to a user-chosen path and
;; reports the task count (the settings feedback line shows it).
(define-rpc (export_backup [path : String] : Int64)
  (define service (require-service))
  (define db (taskly-service-db service))
  (define lists (db-lists db))
  (define tasks (db-tasks db #:view 'all #:show-completed #t #:limit 1000000))
  (define payload
    (hasheq 'format "taskly-backup"
            'version 1
            'exportedAt (local-timestamp)
            'lists (map list->backup-json lists)
            'tasks (map task->backup-json tasks)))
  (with-handlers
      ([exn:fail?
        (lambda (e)
          (raise-taskly 'database 4
                        (format "backup export failed: ~a" (exn-message e))))])
    (call-with-output-file (path->complete-path path) #:exists 'truncate/replace
      (lambda (out) (write-json-pretty payload out))))
  (length tasks))

;; Validates without touching the database: the host shows the counts in its
;; confirmation dialog (PRODUCT-SPEC §2a two-step restore).
(define-rpc (preview_backup [path : String] : BackupPreview)
  (define-values (_lists _tasks list-count task-count) (parse-backup-file path))
  (BackupPreview "taskly-backup" 1 list-count task-count))

;; The confirmed step: replaces the current database's lists and tasks in one
;; transaction (DATA-FORMAT §9). The host must have previewed the same file;
;; re-validation here keeps the database safe even against a changed file.
;; Like open/create, the returned snapshot IS the refresh — no event, so the
;; direct seam and the wire transport behave identically.
(define-rpc (restore_backup [path : String] : Snapshot)
  (define service (require-service))
  (define-values (list-entries tasks _lists _task-counts)
    (parse-backup-file path))
  (db-restore-backup! (taskly-service-db service) list-entries tasks)
  (snapshot->dto service))

(define-rpc (close_database : Void)
  (define service (unbox current-service))
  (when service
    (close-taskly-service service)
    (set-box! current-service #f))
  (void))

(define-rpc (load_snapshot [view : String]
                           [list-id : (Optional Int64)]
                           [show-completed : Bool]
                           : Snapshot)
  (snapshot->dto (require-service)
                 #:view view
                 #:list-id (optional->false list-id)
                 #:show-completed show-completed))

(define-rpc (add_task [text : String]
                      [list-id : (Optional Int64)]
                      [due-date : (Optional String)]
                      [due-time : (Optional String)]
                      [notes : (Optional String)]
                      : Task)
  (define service (require-service))
  (define task
    (service-add-task! service text
                       #:list-id (optional->false list-id)
                       #:due-date (optional->false due-date)
                       #:due-time (optional->false due-time)
                       #:notes (optional->false notes)))
  (publish! service)
  (task->dto task))

(define-rpc (update_task [task : Task] : Task)
  (define service (require-service))
  (define updated (service-update-task! service (dto->task task)))
  (publish! service)
  (task->dto updated))

(define-rpc (update_task_text [id : Int64] [text : String] : Task)
  (define service (require-service))
  (define task (service-update-task-text! service id text))
  (publish! service)
  (task->dto task))

(define-rpc (set_completed [id : Int64] [completed : Bool] : Task)
  (define service (require-service))
  (define task (service-set-completed! service id completed))
  (publish! service)
  (task->dto task))

(define-rpc (delete_task [id : Int64] : Bool)
  (define service (require-service))
  (define deleted? (service-delete-task! service id))
  (when deleted? (publish! service))
  deleted?)

(define-rpc (search_tasks [keyword : String] : (List Task))
  (map task->dto (service-search (require-service) keyword)))

(define-rpc (create_list [name : String]
                         [icon : (Optional String)]
                         [color : (Optional Int64)]
                         : TodoList)
  (define service (require-service))
  (define item
    (service-add-list! service name
                       #:icon (or (optional->false icon) default-list-icon)
                       #:color (or (optional->false color) default-list-color)))
  (publish! service)
  (list->dto item))

(define-rpc (update_list [item : TodoList] : TodoList)
  (define service (require-service))
  (define updated (service-update-list! service (dto->list item)))
  (publish! service)
  (list->dto updated))

(define-rpc (delete_list [id : Int64] : Bool)
  (define service (require-service))
  (define deleted? (service-delete-list! service id))
  (when deleted? (publish! service))
  deleted?)

(define-rpc (default_database : String)
  (path->string (resolve-database-path)))

;; Canonical quick-add/date-expression parsing (CLI-SPEC `--due` grammar).
;; Returns `yyyy-MM-dd` for pure-date intents, `yyyy-MM-dd HH:mm:ss`
;; otherwise — the 10-char shape IS the pure-date signal. Unparseable input
;; raises the validation error; hosts decide how to surface it.
(define-rpc (parse_due [expression : String] : String)
  (define-values (d t) (parse-due-expression expression))
  (if t (format "~a ~a:00" d t) d))

(define-rpc (parse_quick_add [text : String] : QuickAddParse)
  (if (string=? (string-trim text) "")
      (QuickAddParse text (void) (void))
      (let-values ([(clean command) (extract-quick-add-command text)])
        (if (not command)
            (QuickAddParse clean (void) (void))
            (with-handlers
                ([exn:fail:taskly?
                  (lambda (_) (QuickAddParse clean (void) (void)))])
              (let-values ([(d t) (parse-due-expression command)])
                (QuickAddParse clean (nullable d) (nullable t))))))))

;; Reminder policy lives in the shared service. Hosts only schedule polls,
;; localize the returned decision and perform the native OS handoff.
(define-rpc (reminder_decisions [startup : Bool] : (List ReminderDecision))
  (map reminder-decision->dto
       (service-reminder-decisions!
        (require-service) startup
        #:now-date (local-date-string)
        #:now-time (local-time-string))))

(define-rpc (acknowledge_reminder [token : String] [phase : String] : Bool)
  (service-acknowledge-reminder! (require-service) token phase))

(define-rpc (get_settings : Settings)
  (settings->dto))

;; Keys and values are validated here so hosts can persist preferences
;; without each one re-implementing the config grammar.
(define allowed-settings
  '(("language" ("zh" "en"))
    ("theme" ("system" "light" "dark"))
    ("close-to-tray" ("0" "1"))
    ;; Host-declared install shape (Windows: msi vs portable zip; Linux:
    ;; appimage vs deb/rpm vs tarball) — the updater picks the download
    ;; flavor from it (UPDATE.md).
    ("install-flavor" ("zip" "msi" "appimage" "package" "tarball"))
    ;; UPDATE.md auto-check toggle: silent launch/4h checks skip when "0";
    ;; the manual Check for Updates… item always runs.
    ("auto-check-updates" ("0" "1"))))

;; Integer-as-string per DATA-FORMAT §7: sidebar selection, the
;; update-check throttle (shared/spec/UPDATE.md) and the quick-add default
;; list persist as plain integers.
(define integer-settings
  '("last-selected-list-id" "last-update-check" "default-list-id"))

;; Free-form strings: the recorded global-quick-add accelerator
;; (PRODUCT-SPEC §2a — display-only, never registered with the OS).
(define free-settings '("global-quick-add"))

(define-rpc (set_setting [key : String] [value : String] : Settings)
  (define normalized-key (string-downcase (string-trim key)))
  (unless (or (assoc normalized-key allowed-settings)
              (member normalized-key integer-settings)
              (member normalized-key free-settings))
    (error 'set_setting "unknown setting: ~a" normalized-key))
  (cond
    [(assoc normalized-key allowed-settings)
     (unless (member value (cadr (assoc normalized-key allowed-settings)))
       (error 'set_setting "invalid value for ~a: ~a" normalized-key value))]
    [(member normalized-key free-settings)
     (when (> (string-length value) 200)
       (error 'set_setting "invalid value for ~a: ~a" normalized-key value))]
    [else
     (define parsed (string->number (string-trim value)))
     (unless (and parsed (exact-integer? parsed))
       (error 'set_setting "invalid value for ~a: ~a" normalized-key value))])
  (define config (read-config))
  ;; read-config returns a mutable hash — hash-set! (not the
  ;; immutable-only hash-set) or every write would fail and hosts'
  ;; try?-swallowed RPC errors would silently drop preferences.
  (hash-set! config normalized-key (string-trim value))
  (write-config! config)
  (settings->dto))

;; Raw config read for host-side state that has no Settings slot (e.g. the
;; last-update-check throttle, DATA-FORMAT §7). Unset keys read as the empty
;; string so hosts parse a single shape ("value or default").
(define-rpc (get_setting [key : String] : String)
  (config-ref (read-config) (string-downcase (string-trim key)) ""))

;; ------------------------------------------------------------ online update
;; The family pattern (rivet/distribution): this backend verifies and
;; downloads the signed artifact; hosts own installation and the silent
;; 4-hour throttle (last-update-check config key, shared/spec/UPDATE.md).

(define (update-check->record result)
  (define (opt key) (nullable (hash-ref result key #f)))
  (UpdateCheck
   (hash-ref result 'status "error")
   (opt 'message)
   (hash-ref result 'currentVersion app-version)
   (opt 'availableVersion)
   (opt 'build)
   (opt 'publishedAt)
   (opt 'installer)
   (opt 'sizeBytes)))

;; Never raises: network/manifest failures surface as status "error" so a
;; headless check can't take the host down with it.
(define-rpc (check_updates : UpdateCheck)
  (with-handlers
      ([exn:fail?
        (lambda (e)
          (UpdateCheck "error" (nullable (exn-message e)) app-version
                       (void) (void) (void) (void) (void)))])
    (update-check->record (perform-check!))))

;; Runs on a backend worker thread; the host follows progress via
;; update_state. A second call while a transfer is active is the cancellation
;; signal used by the generated clients (keeps the RPC schema backward
;; compatible while making the existing Cancel controls real).
(define-rpc (start_download : Void)
  (with-handlers
      ([exn:fail? (lambda (e) (set-update-error! (exn-message e)))])
    (if (download-running?)
        (cancel-download!)
        (start-download! (taskly-directory))))
  (void))

(define-rpc (update_state : UpdateState)
  (define s (update-state-snapshot))
  (UpdateState
   (hash-ref s 'phase "idle")
   (hash-ref s 'percent 0)
   (nullable (hash-ref s 'message #f))
   (nullable (hash-ref s 'downloadedPath #f))
   (nullable (hash-ref s 'availableVersion #f))))

;; Identity and data locations for the settings 关于 group (#157). Reads
;; only release constants and paths; touches no network and no database.
(define-rpc (app_info : AppInfo)
  (AppInfo app-version
           (symbol->string (platform-symbol))
           (symbol->string (architecture-symbol))
           (path->string (resolve-database-path))
           (path->string (config-file-path))))

;; Native embedded hosts pass anonymous pipe file descriptors here.
(define (start in-fd out-fd)
  (serve-fds in-fd out-fd))

;; Test seam: the generated RPC handlers are plain functions; contract
;; tests import them directly without standing up an RVT1 server.
(module+ rpcs
  (provide get_setting set_setting open_database close_database
           create_database migrate_database
           export_backup preview_backup restore_backup))

;; The managed development host speaks the exact same RVT1 protocol over
;; stdin/stdout. This is deliberately only a transport alternative: the
;; Taskly service and RPC surface remain identical to the embedded host.
(define (start-stdio)
  (serve (current-input-port) (current-output-port)
         ;; serve's own default sink is `void`; pass the file sink so the
         ;; managed dev host records diagnostics like the packaged one.
         #:diagnostic-sink (current-rivet-diagnostic-sink)))

(module+ main
  (start-stdio))
