# Taskly

A focused, keyboard-friendly task manager for macOS, Windows and Linux —
one Racket core driving a single first-party glaze host (web UI) on every
desktop, an agent-facing CLI, and a single local SQLite file.

[![release](https://img.shields.io/github/v/release/turlamai/taskly)](https://github.com/turlamai/taskly/releases/latest) ![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey) ![built with](https://img.shields.io/badge/built%20with-Glaze%20%2B%20Rivet-9333ea) [![CI](https://github.com/turlamai/taskly/actions/workflows/ci.yml/badge.svg)](https://github.com/turlamai/taskly/actions/workflows/ci.yml) [![License](https://img.shields.io/badge/license-BUSL--1.1-blue)](LICENSE)

**English** · [中文](README.zh-CN.md)

Taskly is built on [Rivet](https://github.com/turlamai/rivet) (typed RPC
contract) and [glaze](https://github.com/turlamai/glaze) (window/tray/
hotkey runtime): the entire domain — SQLite storage, scheduling,
natural-language dates, validation, and the CLI — lives in one Racket CS
core, and every desktop gets the same thin first-party host over typed
RPC. Shared domain logic belongs in the backend (reminder
decisions included, #62).

| Desktop | Host |
|---|---|
| macOS 14+ (Apple Silicon + Intel) | glaze web UI (WKWebView) |
| Windows 10+ (x64) | glaze web UI (WebView2) |
| Linux (x64 + ARM64) | glaze web UI (WebKitGTK) |

Mobile is designed, not delivered: the owner decision of 2026-11-22/23
sets the mobile surface as a platform-native app (Swift for iOS/iPadOS,
Kotlin for Android when it starts) with design contracts under
`design/` ([DESIGN.md](design/DESIGN.md)). The glaze host does not extend
to mobile, no mobile project exists yet, and no date is promised.

## Start here

Development preview; no paid checkout is open. A future official desktop purchase will be announced with its delivered terms. Desktop previews for macOS, Windows and Linux. Select the OS and CPU shown on the release asset; mobile and watch applications are not delivered products.

[Installation, first use, privacy, backup and recovery](docs/USER-GUIDE.md) · [简体中文](docs/USER-GUIDE.zh-CN.md)

## Features

- **Reminders-style UI** — smart views (今天 / 计划 / 全部 / 已完成),
  custom lists with emoji icons and 12-color palette, light/dark that
  follows the system, bilingual zh/en with live switch.
- **Quick add with natural-language dates** — type 明天买菜 or
  `standup @9am +1d`; the engine parses the schedule, and the inline
  editor shows it in live date/priority chips as you type.
- **Reminders-parity interactions** — Return expands the row in place
  (title, date/time chips, notes), Esc collapses without leaking the
  draft, click-away commits; completed tasks fold under a collapsible
  header; deletes stage behind a one-step undo banner that restores the
  original row. One web host means the same interaction set on all three
  platforms ([benchmark notes](docs/UX-BENCHMARKS.md)).
- **Anchored task details (all platforms)** — ⓘ opens one layer with
  completion, title, date/time, priority, tags, subtasks, notes, URL and
  list membership; every change saves immediately and closing never
  discards.
- **Reminders (staged)** — the reminder field is editable and persisted,
  but OS notification delivery is staged
  ([#131](https://github.com/turlamai/taskly/issues/131)); no banners are
  promised yet.
- **One data file, where you choose** — first launch asks you to create a
  database in a folder of your choice (`taskly.sqlite`) or open an existing
  one; no default location is assigned silently, and Settings shows the
  current location with reveal, migrate and backup actions. The file is
  SQLite (WAL). Back it up after closing the app;
  live cloud-folder replication is not safe concurrent database sync. The format is documented and stable:
  [DATA-FORMAT](shared/spec/DATA-FORMAT.md).
- **Agent-facing CLI** — `taskly list|add|update|done|rm|search|mklist…`
  with stable `--json` output, fixed exit codes, and byte-level
  cross-platform parity pinned by a 63-case golden suite. Spec:
  [CLI-SPEC](shared/spec/CLI-SPEC.md).
- **Online updates (all platforms)** — silent check at launch (at most
  once every 4 hours, toggleable) plus a manual check in Settings → About;
  the backend verifies the signed
  [update manifest](shared/spec/UPDATE.md) (Ed25519). When a newer version
  exists the app says so and opens the releases page — the current desktop
  host does not download or install in place.

## Honest gaps

- **The release packages don't include a standalone CLI binary yet** —
  the CLI runs from source today (see below); a packaged CLI distribution
  is on the roadmap.
- **Multi-select / batch actions, ↑/↓ row navigation and the shared app
  accelerators (Ctrl/⌘+1…4, N, F, ⇧C)** are benchmark targets, not yet in
  the glaze host ([notes](docs/UX-BENCHMARKS.md)).
- **OS notification delivery is staged** (#131); reminder fields persist
  but nothing fires yet.
- **macOS release signing** — the current tag-release workflow requires Developer ID signing and notarization; local development builds may be ad-hoc signed. Check the published release's trust status for the actual artifact.

## Install

Grab your build from
[Releases](https://github.com/turlamai/taskly/releases/latest):
The installed app is branded **Taskly**; lowercase `taskly` remains the
CLI/package filename slug and does not change download URLs or data paths.

| Platform | Portable zip | Installer |
|---|---|---|
| macOS Apple silicon | `taskly-<version>-macos-arm64.zip` | `taskly-<version>-macos-arm64.dmg` |
| macOS Intel | `taskly-<version>-macos-x64.zip` | `taskly-<version>-macos-x64.dmg` |
| Windows x64 | `taskly-<version>-windows-x64.zip` | `taskly-<version>-windows-x64.msi` |
| Windows ARM64 | runs the x64 build via Windows on ARM's x64 emulation | — |
| Linux x64 | `taskly-<version>-linux-x64.tar.gz` | `taskly-<version>-linux-amd64.deb` / `taskly-<version>-1-linux-x86_64.rpm` / `taskly-<version>-linux-x86_64.AppImage` / `taskly-<version>-linux-x64.flatpak` |
| Linux ARM64 | `taskly-<version>-linux-arm64.tar.gz` | `taskly-<version>-linux-arm64.deb` / `taskly-<version>-1-linux-aarch64.rpm` / `taskly-<version>-linux-aarch64.AppImage` / `taskly-<version>-linux-arm64.flatpak` |

Every release carries a `SHA256SUMS` manifest and a signed
`update-manifest.json` — the update checker's feed. The app checks it
and opens the releases page; installing is manual (download, verify
against `SHA256SUMS`, run the installer or unpack the archive).

The current tag-release workflow requires Developer ID signing, notarization and verification. Older preview artifacts may be ad-hoc signed; consult the release's trust status. Do not disable system-wide protections. Verify the release checksum and use a trusted build; the installed bundle is `/Applications/Taskly.app`.

Linux needs a WebKitGTK 4.1 desktop runtime (unpack the tarball and run
`Taskly`; the webview engine and its system libraries are the only
runtime dependencies — everything else is bundled).

## CLI from source

```bash
git clone https://github.com/turlamai/taskly.git
cd taskly
raco pkg install --auto --no-docs https://github.com/turlamai/rivet.git
racket racket/taskly/cli.rkt add "买牛奶" --due tomorrow --json
racket racket/taskly/cli.rkt install-cli   # shim at ~/.local/bin/taskly
```

## Building from source

Racket CS 9.3+ plus Node 22 / pnpm (web UI) and the glaze runtime deps of
your desktop (WebView2 on Windows, WKWebView on macOS, WebKitGTK 4.1 on
Linux):

```bash
raco pkg install --auto --no-docs https://github.com/turlamai/glaze.git
pnpm install && pnpm check && pnpm build   # web UI
raco glaze build --entry backend/main.rkt --name Taskly \
  --version "$(cat VERSION)" --identifier app.taskly.Taskly --out dist
racket scripts/acceptance/run-suites.rkt   # full current-platform evidence
raco test racket/       # contract tests
python3 shared/cli-golden/runner.py --binary scripts/taskly-cli.sh   # 63-case golden suite
```

## Architecture

```
┌─────────────────────────────┐            ┌────────────────────────────┐
│ glaze host (single)         │            │ Racket CS core             │
│  web UI + tray/hotkey/      │◀── typed ──▶│  db · scheduling ·         │
│  capture/autostart          │  RPC (RVT1)│  validation · reminders    │
│  embedded Racket CS runtime │            │  agent CLI (same domain)   │
└─────────────────────────────┘            └────────────────────────────┘
```

One spec keeps every surface consistent: product behavior
([PRODUCT-SPEC](shared/spec/PRODUCT-SPEC.md)), data format, CLI contract,
design tokens, and the update contract — all under
[shared/spec/](shared/spec/). CI enforces the CLI contract with the golden
suite and byte-identical i18n on every push. The source-controlled
`rivet-acceptance.rktd` additionally requires real RVT1, a glaze build,
and real-window §6 journey evidence on Windows, macOS arm64/x64, and
Linux (executed by `scripts/acceptance/run-suites.rkt`).

## Feedback

Taskly is offline-first and ships no telemetry —
[GitHub issues](https://github.com/turlamai/taskly/issues) are the
feedback channel, with templates for both
[bug reports](https://github.com/turlamai/taskly/issues/new?template=bug_report.md)
and
[feature requests](https://github.com/turlamai/taskly/issues/new?template=feature_request.md).
The About group in Settings links to the same tracker on every platform.

## License

[BUSL-1.1](LICENSE) — source-available; each version converts to MIT on its change date (four years after release, all by 2030-09-28).
