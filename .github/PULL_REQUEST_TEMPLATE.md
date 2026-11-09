<!--
Title format: type(scope): summary — e.g. fix(cli): keep --due errors stable across platforms
-->

## Summary

What changed and why. Link the issue it closes (`Fixes #NNN`) when there is one.

## Platform impact

The RVT1 contract (`racket/taskly/backend.rkt` RPC/Event/State surface) is
cross-platform: changing any of it is a three-platform release, with the
checked-in generated clients regenerated in the same commit.

- [ ] No backend contract changes (RPC/Event/State untouched)
- [ ] `raco rivet build` run; the three tracked clients diff clean
      (`linux/GeneratedBackend.hpp`, `windows/GeneratedBackend.hpp`,
      `macos-host/Sources/RivetHost/GeneratedBackend.swift`)
- [ ] CLI behavior change: `shared/spec/CLI-SPEC.md` updated first and the
      golden suite re-recorded (`shared/cli-golden/`)
- [ ] `scripts/sync-i18n.sh --check` clean for changes under `shared/i18n/`
      or `shared/emoji.json`

## Tests

How this is covered: `raco test racket/`, the golden CLI suite, platform
host builds, `raco rivet acceptance --json`, or a new test added in the
same commit.

## Checklist

- [ ] Release prep only: `VERSION` == `rivet.rktd` == CHANGELOG section
      (`bash scripts/check-release-version.sh`)
- [ ] Docs updated in the same change (README / USER-GUIDE, English + zh-CN)
- [ ] Security-relevant behavior flagged per [SECURITY.md](SECURITY.md)
