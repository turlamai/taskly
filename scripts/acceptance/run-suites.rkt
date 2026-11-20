#lang racket/base

;; Executable acceptance runner for the glaze rewrite (issue #141 slice 5).
;; Reads rivet-acceptance.rktd, runs every suite declared for the current
;; platform, and archives per-suite logs plus a summary under
;; .glaze/acceptance/. A suite passes only when its command exits 0 AND
;; every declared evidence file exists afterwards. Any failure exits 1.
;;
;; Run from the repository root: racket scripts/acceptance/run-suites.rkt

(require json
         racket/file
         racket/port
         racket/runtime-path
         racket/string
         racket/system)

(define-runtime-path manifest-path "../../rivet-acceptance.rktd")

(define platform
  (case (system-type 'os)
    [(windows) 'windows]
    [(macosx) 'macos]
    [(unix) 'linux]
    [else (error 'taskly-acceptance "unsupported platform")]))

(define manifest (call-with-input-file manifest-path read))
(define suites (hash-ref manifest 'suites))

(define evidence-root (build-path (current-directory) ".glaze" "acceptance"))
(make-directory* evidence-root)

(define version
  (string-trim (file->string (build-path (current-directory) "VERSION"))))

(define (resolve-exe name)
  (or (and (equal? name "python3")
           ;; Windows: the Store alias python3.exe silently no-ops; prefer
           ;; the real interpreter (CI images and dev boxes ship `python`).
           (or (and (eq? platform 'windows) (find-executable-path "python"))
               (find-executable-path "python3")
               (find-executable-path "python")))
      (find-executable-path name)
      (error 'taskly-acceptance "executable not found: ~a" name)))

(define (expand arg)
  (if (equal? arg "@VERSION@") version arg))

(define (run-suite suite)
  (define sid (hash-ref suite 'id))
  (define cmd (map expand (hash-ref suite 'command)))
  (define timeout (hash-ref suite 'timeout-seconds 600))
  (define log-path (build-path evidence-root (string-append (symbol->string sid) ".log")))
  (define exe (resolve-exe (car cmd)))
  (printf "[acceptance] ~a: ~a\n" sid (string-join cmd " "))
  (define log-out (open-output-file log-path #:exists 'truncate/replace))
  (define-values (pid _in _out _err)
    (apply subprocess log-out #f log-out exe (cdr cmd)))
  (define watchdog
    (thread (lambda ()
              (sleep timeout)
              (when (eq? (subprocess-status pid) 'running)
                (printf "[acceptance] ~a: timeout after ~as, killing\n" sid timeout)
                (subprocess-kill pid #t)))))
  (subprocess-wait pid)
  (kill-thread watchdog)
  (close-output-port log-out)
  (define exit-code (subprocess-status pid))
  (define ok? (eq? exit-code 0))
  (define missing-evidence
    (if ok?
        (for/list ([ev (in-list (hash-ref suite 'evidence '()))]
                   #:unless (file-exists? (build-path (current-directory) ev)))
          ev)
        '()))
  (when (and ok? (pair? missing-evidence))
    (printf "[acceptance] ~a: missing evidence ~a\n" sid missing-evidence))
  (unless ok?
    (define lines (file->lines log-path))
    (for ([line (in-list (if (> (length lines) 120)
                             (list-tail lines (- (length lines) 120))
                             lines))])
      (printf "[acceptance:~a] ~a\n" sid line)))
  (hash 'id (symbol->string sid)
        'kind (symbol->string (hash-ref suite 'kind))
        'ok (and ok? (null? missing-evidence))
        'exit-code exit-code
        'missing-evidence missing-evidence
        'log (path->string log-path)))

(define results
  (for/list ([suite (in-list suites)]
             #:when (memq platform (hash-ref suite 'platforms)))
    (run-suite suite)))

(call-with-output-file (build-path evidence-root "summary.json")
  #:exists 'truncate/replace
  (lambda (out)
    (write-json (hash 'platform (symbol->string platform)
                      'suites results
                      'all-ok (andmap (lambda (r) (hash-ref r 'ok)) results))
                out)
    (newline out)))

(for ([r (in-list results)])
  (printf "[acceptance] ~a = ~a\n" (hash-ref r 'id) (hash-ref r 'ok)))
(unless (and (pair? results) (andmap (lambda (r) (hash-ref r 'ok)) results))
  (eprintf "[acceptance] product acceptance failed\n")
  (exit 1))
(displayln "[acceptance] ALL PASS")