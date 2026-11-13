#lang racket/base

(provide (struct-out todo-list)
         (struct-out task-item)
         (struct-out subtask)
         default-list-name
         default-list-icon
         default-list-color)

;; Shared domain records. Optional persisted fields use #f in the Racket core;
;; adapters translate #f to the target transport/database null representation.
(struct todo-list (id name icon color pending-count) #:transparent)
;; Subtask text is non-empty (≤500 chars), done is a boolean; order is the
;; stored order.
(struct subtask (text done) #:transparent)
;; priority: 0 none · 1 low · 2 medium · 3 high; tags: (listof string), each
;; non-empty ≤100 chars; subtasks: (listof subtask) in stored order; url: #f
;; or a ≤2048-char string. Schema v5 (DATA-FORMAT.md).
(struct task-item (id list-id text due-date due-time completed created-at notes list-name priority tags subtasks url) #:transparent)

(define default-list-name "工作")
(define default-list-icon "📋")
;; Signed ARGB 0xFF007AFF, matching DATA-FORMAT.md v5.
(define default-list-color -16745729)
