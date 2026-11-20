#lang racket/base

;; Adapter contract test (#141): drive the glaze backend's JSON RPC
;; surface headlessly — the same codec + in-process RVT1 transport the
;; routes use, without a GUI. Runs on every machine (engine acceptance).
;;
;; Isolation mirrors backend-wire-test.rkt: a throwaway taskly home, so
;; no test touches ~/.taskly or the network.

(require glaze/api
         rackunit
         racket/file
         racket/path
         racket/string
         "../rvt1.rkt"
         "../wire-codec.rkt"
         (prefix-in engine: "../../racket/taskly/backend.rkt")
         "../../racket/taskly/paths.rkt")

(define root (make-temporary-file "taskly-adapter-~a" 'directory))
(current-taskly-home root)

(set-rvt1-call! rvt1-call)
(start-rvt1!)

;; The adapter surface must equal the schema surface (the python gate
;; checks the glaze route list; this checks the codec's runtime table).
(check-equal? (length (rpc-names)) 28 "28 RPCs in rivet-schema.json")

;; default_database resolves under the throwaway home.
(define default-db (rpc/json "default_database" (hasheq)))
(check-true (string? default-db))
(check-true (string-prefix? default-db (path->string root)))

;; First-run create → snapshot DTO shape (camelCase keys, record fields).
(define snap (rpc/json "create_database"
                       (hasheq 'folder (path->string root) 'name "Adapter Test")))
(check-true (hash? snap))
(check-true (hash-has-key? snap 'counts))
(check-true (hash-has-key? snap 'lists))
(check-true (hash-has-key? snap 'tasks))
(define counts (hash-ref snap 'counts))
(check-equal? (hash-ref counts 'today) 0)
(check-true (>= (length (hash-ref snap 'lists)) 1) "default list exists")

;; add_task with optional nulls → Task DTO with camelCase keys.
(define task (rpc/json "add_task"
                       (hasheq 'text "adapter task" 'listId 'null
                               'dueDate 'null 'dueTime 'null 'notes 'null)))
(check-true (hash? task))
(check-equal? (hash-ref task 'text) "adapter task")
(check-equal? (hash-ref task 'completed) #f)
(check-true (hash-has-key? task 'listId))
(check-true (hash-has-key? task 'dueDate))
(check-equal? (hash-ref task 'dueDate) 'null)
(define task-id (hash-ref task 'id))
(check-true (exact-integer? task-id))

;; load_snapshot with an optional list-id present and absent.
(define snap2 (rpc/json "load_snapshot"
                        (hasheq 'view "all" 'listId 'null 'showCompleted #t)))
(check-equal? (length (hash-ref snap2 'tasks)) 1)
(define snap3 (rpc/json "load_snapshot"
                        (hasheq 'view "all" 'listId (hash-ref task 'listId)
                                'showCompleted #t)))
(check-equal? (length (hash-ref snap3 'tasks)) 1)

;; set_completed round-trips a Bool; update_task accepts a record DTO.
(define done (rpc/json "set_completed" (hasheq 'id task-id 'completed #t)))
(check-equal? (hash-ref done 'completed) #t)
(define edited (rpc/json "update_task"
                         (hasheq 'task (hash-set done 'text "edited"))))
(check-equal? (hash-ref edited 'text) "edited")

;; search_tasks returns a list of record DTOs.
(define found (rpc/json "search_tasks" (hasheq 'keyword "edited")))
(check-true (list? found))
(check-equal? (length found) 1)
(check-equal? (hash-ref (car found) 'text) "edited")

;; parse_due / parse_quick_add: scalar + record results.
(check-equal? (rpc/json "parse_due" (hasheq 'expression "2099-01-01")) "2099-01-01")
(define qa (rpc/json "parse_quick_add" (hasheq 'text "pay rent @10am")))
(check-equal? (hash-ref qa 'text) "pay rent")
(check-equal? (hash-ref qa 'dueTime) "10:00")

;; settings record DTO.
(define settings (rpc/json "get_settings" (hasheq)))
(check-true (hash-has-key? settings 'language))
(check-true (hash-has-key? settings 'databasePath))

;; Engine validation errors surface as the engine's message (save-lifecycle
;; contract), not a generic failure: the codec raises glaze's bad-param,
;; whose message both carriers pass to the page.
(check-exn exn:fail:glaze:bad-param?
           (lambda () (rpc/json "parse_due" (hasheq 'expression "not a date"))))
(with-handlers ([exn:fail:glaze:bad-param?
                 (lambda (e)
                   (check-true (string-contains? (exn-message e) "Cannot parse")))])
  (rpc/json "parse_due" (hasheq 'expression "not a date at all")))

;; delete_task → Bool; close_database → Void (null on the JSON side).
(check-equal? (rpc/json "delete_task" (hasheq 'id task-id)) #t)
(check-equal? (rpc/json "close_database" (hasheq)) 'null)

(displayln "adapter contract test: all checks passed")