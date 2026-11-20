#hasheq(
 (version . 1)
 ;; Executable acceptance contract for the glaze rewrite (issue #141).
 ;; The native-host / package / native-ui kinds are retired: packaging is
 ;; proven by release.yml + ci.yml package-smoke, and the UI journeys run
 ;; in the REAL glaze window on every platform (web-ui kind, verify.rkt).
 ;; scripts/acceptance/run-suites.rkt executes the suites for the current
 ;; platform and archives evidence under .glaze/acceptance/.
 (requirements
  . (#hasheq((kind . contract) (platforms . (windows macos linux)))
     #hasheq((kind . bridge) (platforms . (windows macos linux)))
     #hasheq((kind . glaze-build) (platforms . (windows macos linux)))
     #hasheq((kind . web-ui) (platforms . (windows macos linux)))
     #hasheq((kind . release) (platforms . (windows macos linux)))))
 (suites
  . (#hasheq((id . core-contract)
             (kind . contract)
             (platforms . (windows macos linux))
             (command . ("raco" "test"
                         "racket/tests/backend-test.rkt"
                         "racket/tests/cli-update-test.rkt"
                         "racket/tests/core-test.rkt"
                         "racket/tests/rivet-schema-test.rkt"
                         "racket/tests/updater-test.rkt"))
             (timeout-seconds . 600))
     #hasheq((id . embedded-wire)
             (kind . bridge)
             (platforms . (windows macos linux))
             (command . ("raco" "test" "racket/tests/backend-wire-test.rkt"))
             (timeout-seconds . 300))
     #hasheq((id . adapter-contract)
             (kind . contract)
             (platforms . (windows macos linux))
             (command . ("raco" "glaze" "schema" "check" "--json"))
             (timeout-seconds . 300))
     #hasheq((id . rpc-surface)
             (kind . contract)
             (platforms . (windows macos linux))
             (command . ("python3" "scripts/check-rpc-surface.py"))
             (timeout-seconds . 120))
     #hasheq((id . glaze-build)
             (kind . glaze-build)
             (platforms . (windows macos linux))
             (command . ("raco" "glaze" "build"
                         "--entry" "backend/main.rkt"
                         "--name" "Taskly"
                         "--version" "@VERSION@"
                         "--identifier" "app.taskly.Taskly"
                         "--out" ".glaze/acceptance/build"))
             (timeout-seconds . 1800))
     #hasheq((id . web-ui-journeys)
             (kind . web-ui)
             (platforms . (windows macos linux))
             (command . ("racket" "verify.rkt"))
             (timeout-seconds . 900)
             (evidence . (".glaze/verify/taskly-window.png"
                          ".glaze/verify/taskly-capture.png"
                          ".glaze/verify/taskly-e2e.png")))
     #hasheq((id . release-update)
             (kind . release)
             (platforms . (windows macos linux))
             (command . ("racket" "scripts/acceptance/release-update.rkt"))
             (timeout-seconds . 900)
             (evidence . (".rivet/acceptance/release-update.json"))))))