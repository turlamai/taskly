# Security Policy

Taskly handles sensitive data by design: task contents, notes and due
dates live in the local data directory (`~/.taskly/`) and reminders are
scheduled from them. Reports are taken seriously and handled quickly.

## Reporting a vulnerability

Email **security@jrtx.site** (or open a GitHub security advisory on this
repository). Include reproduction steps, affected versions, and your
assessment of impact. You will get an acknowledgment within 72 hours.

Please do not open public issues for security problems.

## Scope

In scope:

- The RVT1 RPC/Event/State boundary between the embedded Racket core and
  the hosts (`racket/taskly/backend.rkt` and the generated clients under
  `macos-host/Sources/RivetHost/`, `windows/`, `linux/`)
- Update trust: Ed25519 manifest verification, embedded key handling and
  artifact integrity (`racket/taskly/updater.rkt`,
  `macos-host/Sources/RivetHost/UpdateService.swift`,
  `scripts/make-update-manifest.sh`; contract: `shared/spec/UPDATE.md`)
- Local data handling: the `~/.taskly/` directory (`tasks.db`,
  `config.ini`, WAL sidecars) and the CLI — its database access, the
  `check-update` network path, and `install-cli`/`uninstall-cli` writes
  to `~/.local/bin`, shell rc files and `HKCU\Environment\Path`
- Reminder eligibility and notification failure handling: a denied
  permission or failed delivery must disable notifications for the
  session, never crash
- Documented claims in `shared/spec/` that exceed actual behavior

Out of scope: social engineering, physical access attacks, and
vulnerabilities in the OS-provided UI toolkits the hosts consume
(SwiftUI/AppKit, WinUI 3, GTK 4).

## Design notes reviewers should know

- The backend binds no network ports. The Racket core is embedded in
  each host process through Rivet's stable C ABI; host/core traffic is
  the typed RVT1 boundary, not a socket. The update feed is the
  application's only network use — no telemetry, no accounts. The macOS
  bundle ships an `InternetAccessPolicy.plist` declaring the feed hosts.
- **Updates and installer trust are different layers.** The Ed25519
  signed manifest (key id `taskly-2026-10`) and the artifact's signed
  size + SHA-256 are verified before any install step — in the backend
  updater (`racket/taskly/updater.rkt`) and, on macOS, again in the host
  via CryptoKit (`UpdateService.swift`). The public key is embedded in
  both files; feed URLs are pinned to the canonical GitHub release
  location and checked by `scripts/check-update-feed-urls.py`. A
  plain-http feed fails closed.
- **The signed feed does not imply a publisher-signed installer.** macOS
  artifacts are ad-hoc signed, not Developer ID signed or notarized —
  release titles deliberately carry "(unsigned evaluation)". Production
  installer trust, upgrade and fresh-machine gates are tracked in
  [#80](https://github.com/turlamai/taskly/issues/80). Do not represent
  current builds as an independently trusted publisher identity.
- **Linux deb/rpm upgrades are owned by the system package manager**;
  the app downloads and verifies but never self-swaps a system-managed
  prefix. The AppImage replaces itself in place; Windows portable zip
  and MSI hand off after app exit; tarballs are manual.
- Installers and updaters replace application files only — they must
  never edit or remove `~/.taskly/`. Uninstalling the app also preserves
  the data directory; deleting data is a separate, explicit action.
- Task data is stored locally as SQLite (WAL mode) and is not
  encrypted; syncing `.taskly/` through a cloud-drive folder is a
  supported setup. Access controls ultimately depend on OS user
  permissions — never assume local storage is protected from programs
  running as the same user.
- Treat update-failure recovery as security-relevant: a failed swap must
  leave the previous install runnable, and a failed verification must
  never let unverified bytes reach an install destination.

## Supported versions

Security fixes land on `main` first and ship with the next tagged
release. During the 0.x developer preview there is no LTS branch.
