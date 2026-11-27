<!--
Title format: type(scope): summary — e.g. fix(cli): keep --due errors stable across platforms
-->

## Summary

What changed and why. Link the issue it closes (`Fixes #NNN`) when there is one.

## Platform impact

The RVT1 contract (`racket/taskly/backend.rkt` RPC/Event/State surface) is
cross-platform: changing any of it is a three-platform release, with the
checked-in generated surfaces regenerated in the same commit
(`scripts/gen-rpc-types.py` → `packages/core/src/rpc.ts`, `raco glaze schema
write` → `glaze-schema.json`).

- [ ] No backend contract changes (RPC/Event/State untouched)
- [ ] Contract changed: both generated surfaces regenerated and
      `scripts/check-rpc-surface.py` + `raco glaze schema check --json` clean
- [ ] CLI behavior change: `shared/spec/CLI-SPEC.md` updated first and the
      golden suite re-recorded (`shared/cli-golden/`)
- [ ] `scripts/sync-i18n.sh --check` clean for changes under `shared/i18n/`
      or `shared/emoji.json`

## Tests

How this is covered: `raco test racket/`, the golden CLI suite, the glaze
adapter tests, `racket verify.rkt` (real-window §6 journeys on the three
platforms in CI), `racket scripts/acceptance/run-suites.rkt` for a release
slice, or a new test added in the same commit.

## Checklist

- [ ] Release prep only: `VERSION` == `rivet.rktd` == CHANGELOG section
      (`bash scripts/check-release-version.sh`)
- [ ] Docs updated in the same change (README / USER-GUIDE, English + zh-CN)
- [ ] Security-relevant behavior flagged per [SECURITY.md](../SECURITY.md)
