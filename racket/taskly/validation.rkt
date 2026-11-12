#lang racket/base

(require racket/string
         "errors.rkt"
         "model.rkt")

(provide max-task-text-length
         max-list-name-length
         max-search-keyword-length
         max-tag-length
         max-subtask-text-length
         max-url-length
         min-year
         max-year
         validate-task-text!
         validate-list-name!
         validate-search-keyword!
         validate-task-priority!
         validate-task-tags!
         validate-task-subtasks!
         validate-task-url!)

(define max-task-text-length 1000)
(define max-list-name-length 100)
(define max-search-keyword-length 200)
(define max-tag-length 100)
(define max-subtask-text-length 500)
(define max-url-length 2048)
(define min-year 1900)
(define max-year 2100)

(define (blank? value)
  (or (not (string? value))
      (string=? "" (string-trim value))))

(define (validate-task-text! text)
  (when (blank? text)
    (raise-taskly 'validation 2 "Please enter a task description."))
  (when (> (string-length text) max-task-text-length)
    (raise-taskly 'validation 2
                  (format "Task description must be ~a characters or fewer." max-task-text-length)))
  (string-trim text))

(define (validate-list-name! name)
  (when (blank? name)
    (raise-taskly 'validation 2 "Please enter a list name."))
  (when (> (string-length name) max-list-name-length)
    (raise-taskly 'validation 2
                  (format "List name must be ~a characters or fewer." max-list-name-length)))
  (string-trim name))

(define (validate-search-keyword! keyword)
  (unless (string? keyword)
    (raise-taskly 'validation 2 "Search keyword must be text."))
  (when (> (string-length keyword) max-search-keyword-length)
    (raise-taskly 'validation 2
                  (format "Search keyword must be ~a characters or fewer." max-search-keyword-length)))
  (string-trim keyword))

(define (validate-task-priority! priority)
  (unless (memv priority '(0 1 2 3))
    (raise-taskly 'validation 2 "Priority must be an integer from 0 to 3."))
  priority)

(define (validate-task-tags! tags)
  (unless (list? tags)
    (raise-taskly 'validation 2 "Tags must be a list."))
  (for/list ([tag tags])
    (unless (string? tag)
      (raise-taskly 'validation 2 "Tags must be text."))
    (when (blank? tag)
      (raise-taskly 'validation 2 "Tags cannot be empty."))
    (when (> (string-length tag) max-tag-length)
      (raise-taskly 'validation 2
                    (format "Tags must be ~a characters or fewer." max-tag-length)))
    (string-trim tag)))

(define (validate-task-subtasks! subtasks)
  (unless (list? subtasks)
    (raise-taskly 'validation 2 "Subtasks must be a list."))
  (for/list ([item subtasks])
    (unless (subtask? item)
      (raise-taskly 'validation 2 "Subtasks must be text/done pairs."))
    (unless (boolean? (subtask-done item))
      (raise-taskly 'validation 2 "Subtask done must be a boolean."))
    (unless (string? (subtask-text item))
      (raise-taskly 'validation 2 "Subtasks must be text."))
    (when (blank? (subtask-text item))
      (raise-taskly 'validation 2 "Subtasks cannot be empty."))
    (when (> (string-length (subtask-text item)) max-subtask-text-length)
      (raise-taskly 'validation 2
                    (format "Subtasks must be ~a characters or fewer." max-subtask-text-length)))
    (struct-copy subtask item [text (string-trim (subtask-text item))])))

(define (validate-task-url! url)
  (cond
    [(not url) #f]
    [(blank? url) #f]
    [(> (string-length (string-trim url)) max-url-length)
     (raise-taskly 'validation 2
                   (format "URLs must be ~a characters or fewer." max-url-length))]
    [else (string-trim url)]))
