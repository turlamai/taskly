# Contributing to Taskly

Thank you for looking under the hood. Taskly is source-available
(BUSL-1.1, see [LICENSE](LICENSE)): by submitting a pull request you
agree your contribution is licensed under BUSL-1.1, with the same MIT
change date as the rest of the Work.

## Ground rules

1. **The wire contract is cross-platform.** `racket/taskly/backend.rkt`
   declares the typed RPC/Event/State surface. Changing any of it is a
   three-platform release: regenerate the checked-in client and route
   baseline with `python3 scripts/gen-rpc-types.py`
   (`packages/core/src/rpc.ts`) and `raco glaze schema write`
   (`glaze-schema.json`) in the same commit, add the 1:1 adapter route in
   `backend/main.rkt`, and keep `scripts/check-rpc-surface.py` green —
   generated files are build inputs, never hand-edit them. User-visible
   strings live in `shared/i18n/{zh,en}.json`; both languages must keep
   exact key parity (`scripts/sync-i18n.sh --check`).
2. **The golden suite pins the CLI contract.** Identical argv must
   produce identical stdout/stderr/exit codes on every platform
   (`shared/cli-golden/`; spec: `shared/spec/CLI-SPEC.md`). Change the
   spec first, then `--record`, then review the diff — spec, goldens
   and implementation land in the same commit. Never weaken a
   requirement in `rivet-acceptance.rktd` to make a change green.
3. **Fail honestly.** Unopenable databases exit 4 with the error on
   stderr; reminder delivery is staged (#131) and when OS notifications
   return, denied permission disables them for the session; a failed
   update verification aborts and the running version keeps working.
   Report what failed and what to do next. No silent fallbacks.
4. **Privacy is a feature.** The signed update feed is the
   application's only network use. No telemetry, no accounts. New
   storage stays under the platform data directory (`~/.taskly/`,
   contract: `shared/spec/DATA-FORMAT.md`).
5. **Tests pin contracts.** If you change behavior a test covers,
   change the test in the same commit and say why.

## Before you push

```bash
raco test racket/                                             # core contract tests
python3 shared/cli-golden/runner.py --binary scripts/taskly-cli.sh
scripts/sync-i18n.sh --check
bash scripts/check-release-version.sh
python3 scripts/check-update-feed-urls.py
python3 scripts/check-rpc-surface.py
bash scripts/check-dependency-pins.sh
pnpm install && pnpm check && pnpm build                      # web UI
racket backend/tests/adapter-test.rkt                         # headless adapter contract
```

These mirror the CI `contract`, `frontend` and `core` jobs. The glaze
host builds and runs its real-window acceptance in its own CI jobs
(`acceptance.yml`); if you touch `backend/` or `apps/desktop/`, say
whether you were able to run `racket verify.rkt` locally (needs a
graphical session).

## Areas that especially want help

- Production installer trust: Developer ID signing, notarization and
  the fresh-machine gates ([#80](https://github.com/turlamai/taskly/issues/80))
- Keeping the Chinese user path in lockstep with the English one
  (`README.zh-CN.md`, `docs/USER-GUIDE.zh-CN.md`) — the language policy
  in [AGENTS.md](AGENTS.md) requires reciprocal updates

## Reporting issues

Include: OS + version, Taskly version (`taskly version`, or the About
dialog), installation shape (DMG / portable zip / MSI / AppImage /
deb / rpm / tarball), steps to reproduce, and for CLI issues the exact
argv plus the JSON error. For update failures, include the error text
from the dialog (selectable on macOS/Linux; "copy error" on Windows).
Security issues go through [SECURITY.md](SECURITY.md), not public
issues.
