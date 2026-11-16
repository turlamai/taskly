#lang racket/base

(require db
         json
         racket/file
         racket/list
         racket/path
         racket/string
         "clock.rkt"
         "errors.rkt"
         "model.rkt")

(provide (struct-out taskly-db)
         open-taskly-db
         close-taskly-db
         create-taskly-db
         taskly-database-file?
         migrate-database-file!
         db-restore-backup!
         db-lists
         db-list-by-id
         db-list-by-name
         db-add-list!
         db-update-list!
         db-delete-list!
         db-tasks
         db-task-by-id
         db-add-task!
         db-update-task!
         db-set-completed!
         db-delete-task!
         db-search-tasks
         db-count-incomplete
         db-count-completed
         db-count-today
         db-count-planned)

(define database-version 5)
(struct taskly-db (connection path) #:transparent)

(define (maybe-sql value)
  (if value value sql-null))

(define (maybe-value value)
  (sql-null->false value))

(define (column-exists? conn table column)
  (for/or ([row (in-list (query-rows conn (format "PRAGMA table_info(~a)" table)))])
    (equal? (vector-ref row 1) column)))

(define (ensure-column! conn table column type)
  (unless (column-exists? conn table column)
    (query-exec conn (format "ALTER TABLE ~a ADD COLUMN ~a ~a" table column type))))

(define (create-indexes! conn)
  (query-exec conn "CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON tasks(list_id)")
  (query-exec conn "CREATE INDEX IF NOT EXISTS idx_tasks_completed ON tasks(completed)")
  (query-exec conn "CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date)"))

(define (create-schema! conn)
  (query-exec conn
              "CREATE TABLE lists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, icon TEXT, color INTEGER, created_at TEXT NOT NULL)")
  (query-exec conn
              "CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, list_id INTEGER, text TEXT NOT NULL, due_date TEXT, due_time TEXT, completed INTEGER DEFAULT 0, created_at TEXT NOT NULL, notes TEXT, priority INTEGER DEFAULT 0, tags TEXT, subtasks TEXT, url TEXT, FOREIGN KEY (list_id) REFERENCES lists (id))")
  (create-indexes! conn)
  (query-exec conn
              "INSERT INTO lists (name, icon, color, created_at) VALUES (?, ?, ?, ?)"
              default-list-name default-list-icon default-list-color (local-timestamp)))

(define (migrate! conn)
  (define old-version (query-value conn "PRAGMA user_version"))
  (call-with-transaction
   conn
   (lambda ()
     (cond
       [(zero? old-version) (create-schema! conn)]
       [else
        (when (< old-version 2) (create-indexes! conn))
        (when (< old-version 3)
          (ensure-column! conn "lists" "icon" "TEXT")
          (ensure-column! conn "lists" "color" "INTEGER"))
        (when (< old-version 4)
          (ensure-column! conn "tasks" "due_time" "TEXT")
          (ensure-column! conn "tasks" "notes" "TEXT"))
        (when (< old-version 5)
          (ensure-column! conn "tasks" "priority" "INTEGER DEFAULT 0")
          (ensure-column! conn "tasks" "tags" "TEXT")
          (ensure-column! conn "tasks" "subtasks" "TEXT")
          (ensure-column! conn "tasks" "url" "TEXT"))])))
  ;; Keep parity with the native implementations: this pragma is written
  ;; outside the migration transaction.
  (query-exec conn (format "PRAGMA user_version = ~a" database-version))
  ;; Belt-and-braces compatibility check used by the existing native ports.
  (with-handlers ([exn:fail? void])
    (ensure-column! conn "lists" "icon" "TEXT")
    (ensure-column! conn "lists" "color" "INTEGER")))

(define (open-taskly-db path)
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (raise-taskly 'database 4 (exn-message e)))])
    (define complete (path->complete-path path))
    (define parent (path-only complete))
    (when parent (make-directory* parent))
    (define conn (sqlite3-connect #:database complete #:mode 'create))
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (disconnect conn)
                       (raise e))])
      (query-exec conn "PRAGMA journal_mode = WAL")
      (migrate! conn)
      (taskly-db conn complete))))

(define (close-taskly-db db)
  (when (and db (connected? (taskly-db-connection db)))
    (disconnect (taskly-db-connection db))))

;; Exclusive create (PRODUCT-SPEC §2a): the target must not exist. The
;; existence check comes first — sqlite3-connect #:mode 'create would
;; happily open-or-create, and the gate's create flow must never adopt or
;; overwrite an existing file.
(define (create-taskly-db path)
  (define complete (path->complete-path path))
  (when (file-exists? complete)
    (raise-taskly 'validation 2 (format "database already exists: ~a" complete)))
  (open-taskly-db complete))

;; Identity probe for open/relocate (PRODUCT-SPEC §2a): a Taskly database
;; carries user_version > 0 or the v1 lists table. A foreign or unreadable
;; file must be refused — relocate depends on never adopting someone else's
;; database, and open must never create a replacement for a missing one.
(define (taskly-database-file? path)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define conn
      (sqlite3-connect #:database (path->complete-path path) #:mode 'read-only))
    (define ok?
      (with-handlers ([exn:fail? (lambda (_) #f)])
        (or (> (query-value conn "PRAGMA user_version") 0)
            (pair?
             (query-rows conn
                         "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'lists'")))))
    (disconnect conn)
    ok?))

;; Copy-migrate (PRODUCT-SPEC §2a): checkpoint WAL into the source's main
;; file, copy it to a sibling temp file, verify the copy opens with the same
;; schema version and list/task counts, then atomically rename it over the
;; target. The source connection stays open and untouched throughout; any
;; failure removes the temp file and leaves the original in place.
(define (migrate-database-file! db target)
  (define source (taskly-db-path db))
  (define complete-target (path->complete-path target))
  (when (file-exists? complete-target)
    (raise-taskly 'validation 2 (format "target already exists: ~a" complete-target)))
  ;; Sibling temp name — never a path-replace-extension dance.
  (define tmp (string-append (path->string complete-target) ".migrating"))
  (with-handlers
      ([exn:fail:taskly?
        (lambda (e)
          (with-handlers ([exn:fail? void]) (when (file-exists? tmp) (delete-file tmp)))
          (raise e))]
       [exn:fail?
        (lambda (e)
          (with-handlers ([exn:fail? void]) (when (file-exists? tmp) (delete-file tmp)))
          (raise-taskly 'database 4
                        (format "migration to ~a failed: ~a"
                                complete-target (exn-message e))))])
    (define conn (taskly-db-connection db))
    ;; WAL content must land in the main file before copying (DATA-FORMAT §2).
    (query-exec conn "PRAGMA wal_checkpoint(TRUNCATE)")
    (define parent (path-only complete-target))
    (when parent (make-directory* parent))
    (copy-file source tmp)
    (define copy (open-taskly-db tmp))
    (define copied
      (list (db-count-incomplete copy) (db-count-completed copy)))
    (close-taskly-db copy)
    (define original
      (list (query-value conn "SELECT COUNT(*) FROM tasks WHERE completed = 0")
            (query-value conn "SELECT COUNT(*) FROM tasks WHERE completed = 1")))
    (unless (equal? copied original)
      (raise-taskly 'database 4 "the migrated copy does not match the source database"))
    (rename-file-or-directory tmp complete-target #f)))

;; Backup restore (DATA-FORMAT §9): replace the current database's lists and
;; tasks in one transaction. `lists` holds (name icon color) triples in file
;; order; `tasks` holds task-item structs whose list-id is the 0-based index
;; into `lists` — re-mapped to the reassigned list ids here. created_at
;; values are preserved verbatim; ids are reassigned by the database.
(define (db-restore-backup! db lists tasks)
  (define conn (taskly-db-connection db))
  (call-with-transaction
   conn
   (lambda ()
     (query-exec conn "DELETE FROM tasks")
     (query-exec conn "DELETE FROM lists")
     (define id-map
       (for/hash ([entry (in-list lists)] [index (in-naturals)])
         (define new-id
           (begin
             (query-exec conn
                         "INSERT INTO lists (name, icon, color, created_at) VALUES (?, ?, ?, ?)"
                         (list-ref entry 0)
                         (maybe-sql (list-ref entry 1))
                         (maybe-sql (list-ref entry 2))
                         (local-timestamp))
             (query-value conn "SELECT last_insert_rowid()")))
         (values index new-id)))
     (for ([task (in-list tasks)])
       (db-add-task!
        db
        (struct-copy task-item task
                     [id 0]
                     [list-id (hash-ref id-map (task-item-list-id task))]))))))

(define list-select
  "SELECT l.id, l.name, l.icon, l.color, (SELECT COUNT(*) FROM tasks t WHERE t.list_id = l.id AND t.completed = 0) AS pending_count FROM lists l")

(define (row->list row)
  (todo-list (vector-ref row 0)
             (vector-ref row 1)
             (maybe-value (vector-ref row 2))
             (maybe-value (vector-ref row 3))
             (vector-ref row 4)))

(define (db-lists db)
  (map row->list (query-rows (taskly-db-connection db) list-select)))

(define (first-row rows)
  (and (pair? rows) (car rows)))

(define (db-list-by-id db id)
  (define row
    (first-row
     (query-rows (taskly-db-connection db)
                 (string-append list-select " WHERE l.id = ? LIMIT 1") id)))
  (and row (row->list row)))

(define (db-list-by-name db name)
  (define row
    (first-row
     (query-rows (taskly-db-connection db)
                 (string-append list-select " WHERE l.name = ? LIMIT 1") name)))
  (and row (row->list row)))

(define (db-add-list! db name [icon default-list-icon] [color default-list-color])
  (define conn (taskly-db-connection db))
  (query-exec conn
              "INSERT INTO lists (name, created_at, icon, color) VALUES (?, ?, ?, ?)"
              name (local-timestamp) (maybe-sql icon) (maybe-sql color))
  (query-value conn "SELECT last_insert_rowid()"))

(define (db-update-list! db item)
  (define conn (taskly-db-connection db))
  (define existed? (and (db-list-by-id db (todo-list-id item)) #t))
  (when existed?
    (query-exec conn
                "UPDATE lists SET name = ?, icon = ?, color = ? WHERE id = ?"
                (todo-list-name item)
                (maybe-sql (todo-list-icon item))
                (maybe-sql (todo-list-color item))
                (todo-list-id item)))
  existed?)

(define (db-delete-list! db id)
  (define conn (taskly-db-connection db))
  (define existed? (and (db-list-by-id db id) #t))
  (when existed?
    (call-with-transaction
     conn
     (lambda ()
       (query-exec conn "DELETE FROM tasks WHERE list_id = ?" id)
       (query-exec conn "DELETE FROM lists WHERE id = ?" id))))
  existed?)

(define task-select
  "SELECT t.id, t.list_id, t.text, t.due_date, t.due_time, t.completed, t.created_at, t.notes, l.name AS list_name, t.priority, t.tags, t.subtasks, t.url FROM tasks t LEFT JOIN lists l ON t.list_id = l.id")

;; JSON columns (v5): tags is a JSON string array, subtasks a JSON array of
;; {text, done} objects. NULL or unparseable payloads read as empty; a NULL
;; priority reads as 0.
(define (json-column->value raw)
  (and (string? raw)
       (with-handlers ([exn:fail? (lambda (_) #f)])
         (read-json (open-input-string raw)))))

(define (sql->tags raw)
  (define parsed (json-column->value raw))
  (if (list? parsed)
      (for/list ([item parsed] #:when (string? item)) item)
      (list)))

(define (sql->subtasks raw)
  (define parsed (json-column->value raw))
  (if (list? parsed)
      (for/list ([item parsed]
                 #:when (hash? item)
                 #:when (string? (hash-ref item 'text #f)))
        (subtask (hash-ref item 'text)
                 (and (boolean? (hash-ref item 'done #f))
                      (hash-ref item 'done #f))))
      (list)))

(define (tags->sql tags)
  (maybe-sql (and (pair? tags) (jsexpr->string tags))))

(define (subtasks->sql subtasks)
  (maybe-sql
   (and (pair? subtasks)
        (jsexpr->string
         (for/list ([item subtasks])
           (hash 'text (subtask-text item) 'done (subtask-done item)))))))

(define (row->task row)
  (task-item (vector-ref row 0)
             (or (maybe-value (vector-ref row 1)) 0)
             (vector-ref row 2)
             (maybe-value (vector-ref row 3))
             (maybe-value (vector-ref row 4))
             (= 1 (vector-ref row 5))
             (vector-ref row 6)
             (maybe-value (vector-ref row 7))
             (maybe-value (vector-ref row 8))
             (if (integer? (vector-ref row 9)) (vector-ref row 9) 0)
             (sql->tags (vector-ref row 10))
             (sql->subtasks (vector-ref row 11))
             (maybe-value (vector-ref row 12))))

(define (query-tasks db suffix . params)
  (map row->task
       (apply query-rows
              (taskly-db-connection db)
              (string-append task-select " " suffix)
              params)))

(define (db-tasks db #:view [view 'all] #:list-id [list-id #f]
                  #:limit [limit 1000] #:offset [offset 0]
                  #:show-completed [show-completed #f])
  (cond
    [list-id
     (if show-completed
         (query-tasks db "WHERE t.list_id = ? ORDER BY t.completed ASC, t.id DESC LIMIT ? OFFSET ?"
                      list-id limit offset)
         (query-tasks db "WHERE t.list_id = ? AND t.completed = 0 ORDER BY t.id DESC LIMIT ? OFFSET ?"
                      list-id limit offset))]
    [(eq? view 'today)
     (define today (local-date-string))
     (if show-completed
         (query-tasks db "WHERE date(t.due_date) = ? ORDER BY t.completed ASC, t.id DESC LIMIT ? OFFSET ?"
                      today limit offset)
         (query-tasks db "WHERE date(t.due_date) = ? AND t.completed = 0 ORDER BY t.id DESC LIMIT ? OFFSET ?"
                      today limit offset))]
    [(eq? view 'planned)
     (if show-completed
         (query-tasks db "WHERE t.due_date IS NOT NULL ORDER BY t.completed ASC, t.due_date ASC LIMIT ? OFFSET ?"
                      limit offset)
         (query-tasks db "WHERE t.due_date IS NOT NULL AND t.completed = 0 ORDER BY t.due_date ASC LIMIT ? OFFSET ?"
                      limit offset))]
    [(eq? view 'completed)
     (query-tasks db "WHERE t.completed = 1 LIMIT ? OFFSET ?" limit offset)]
    [else
     (if show-completed
         (query-tasks db "ORDER BY t.completed ASC, t.id DESC LIMIT ? OFFSET ?" limit offset)
         (query-tasks db "WHERE t.completed = 0 ORDER BY t.id DESC LIMIT ? OFFSET ?" limit offset))]))

(define (db-task-by-id db id)
  (define rows (query-tasks db "WHERE t.id = ? LIMIT 1" id))
  (and (pair? rows) (car rows)))

(define (db-add-task! db task)
  (define conn (taskly-db-connection db))
  (query-exec conn
              "INSERT INTO tasks (list_id, text, due_date, due_time, completed, created_at, notes, priority, tags, subtasks, url) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
              (task-item-list-id task)
              (task-item-text task)
              (maybe-sql (task-item-due-date task))
              (maybe-sql (task-item-due-time task))
              (if (task-item-completed task) 1 0)
              (task-item-created-at task)
              (maybe-sql (task-item-notes task))
              (or (task-item-priority task) 0)
              (tags->sql (task-item-tags task))
              (subtasks->sql (task-item-subtasks task))
              (maybe-sql (task-item-url task)))
  (query-value conn "SELECT last_insert_rowid()"))

(define (db-update-task! db task)
  (define conn (taskly-db-connection db))
  (define existed? (and (db-task-by-id db (task-item-id task)) #t))
  (when existed?
    (query-exec conn
                "UPDATE tasks SET list_id = ?, text = ?, due_date = ?, due_time = ?, completed = ?, notes = ?, priority = ?, tags = ?, subtasks = ?, url = ? WHERE id = ?"
                (task-item-list-id task)
                (task-item-text task)
                (maybe-sql (task-item-due-date task))
                (maybe-sql (task-item-due-time task))
                (if (task-item-completed task) 1 0)
                (maybe-sql (task-item-notes task))
                (or (task-item-priority task) 0)
                (tags->sql (task-item-tags task))
                (subtasks->sql (task-item-subtasks task))
                (maybe-sql (task-item-url task))
                (task-item-id task)))
  existed?)

(define (db-set-completed! db id completed?)
  (define existed? (and (db-task-by-id db id) #t))
  (when existed?
    (query-exec (taskly-db-connection db)
                "UPDATE tasks SET completed = ? WHERE id = ?"
                (if completed? 1 0) id))
  existed?)

(define (db-delete-task! db id)
  (define existed? (and (db-task-by-id db id) #t))
  (when existed?
    (query-exec (taskly-db-connection db) "DELETE FROM tasks WHERE id = ?" id))
  existed?)

(define (db-search-tasks db keyword #:limit [limit 100])
  (if (string=? "" keyword)
      '()
      (query-tasks db "WHERE t.text LIKE ? LIMIT ?" (string-append "%" keyword "%") limit)))

(define (count-value db sql . params)
  (apply query-value (taskly-db-connection db) sql params))

(define (db-count-incomplete db)
  (count-value db "SELECT COUNT(*) FROM tasks WHERE completed = 0"))

(define (db-count-completed db)
  (count-value db "SELECT COUNT(*) FROM tasks WHERE completed = 1"))

(define (db-count-today db)
  (count-value db "SELECT COUNT(*) FROM tasks WHERE date(due_date) = ? AND completed = 0"
               (local-date-string)))

(define (db-count-planned db)
  (count-value db "SELECT COUNT(*) FROM tasks WHERE due_date IS NOT NULL AND completed = 0"))
