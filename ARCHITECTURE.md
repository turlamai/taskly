# Taskly Architecture — Shared Racket Core + Single glaze Host

> Status: **Mainline** — the Rivet rebuild is the product line (single `main`
> branch); one glaze host (web UI + thin native capabilities) ships on all
> three desktop platforms from it. The migration history lives in git (the
> pre-rewrite native line ends at commit `51c9c1c`; the three-native-host
> line ends with the glaze rewrite, issue #141).

## Decision

Taskly converged from three duplicated application implementations toward
one Racket application core connected to a single first-party host through
Rivet (typed RPC contract) and glaze (window/tray/hotkey/autostart runtime).

The product rule is:

> Share product behavior; keep platform behavior in one thin host.

Racket owns behavior that must be identical everywhere. The web UI owns
presentation; the glaze adapter owns the small set of OS capabilities a
browser page cannot reach (native pickers, tray, global hotkey, autostart,
quick-capture window).

## Ownership boundary

| Concern | Owner |
|---|---|
| SQLite schema/migrations, queries | Racket core |
| config and DB path resolution | Racket core |
| validation, date parsing, filtering | Racket core |
| reminder eligibility, startup summary, session de-duplication and handoff state | Racket core |
| task/list state transitions | Racket core |
| CLI semantics and exit classification | Racket core |
| RPC/state/events contract, typed DTO schema | Rivet (`rivet-schema.json`) |
| Racket CS embedding/lifecycle, typed routes, RVT1 transport | glaze adapter (`backend/`) |
| view composition, drafts, autosave, undo staging | web UI (`apps/desktop/`) |
| IME, keyboard, accessibility | web platform (single host, all OSes) |
| file dialogs, tray, global hotkey, autostart, capture window | glaze thin host (`backend/`) |
| signing/package/update integration | glaze build + release tooling (feed stays rivet format) |

## Target data flow

```text
DOM event (real user or acceptance harness)
    │
    ▼
Production handler (apps/desktop/src/main.ts …)
    │
    ▼
Store (snapshot + staged delete + preview generation)
    │
    ▼
Generated typed client (packages/core/src/rpc.ts)
    │  native GLZ1 carrier ── or ── HTTP fetch (dev adapter)
    ▼
glaze typed route (backend/main.rkt, 1:1 rivet-schema.json)
    │
    ▼
In-process RVT1 pipe pair → embedded Racket Taskly service
    │
    ├── validation / date / commands
    ├── SQLite v4 repository
    └── state + domain events (`changed` publish)
    │
    ▼
Rivet response / glaze event bus (GLZ1 push or SSE)
    │
    ▼
Store refresh → render (search stays owner; drafts survive)
```

UI code must not contain a second implementation of Taskly business rules.
The engine is unchanged by the host rewrite: same RPC surface, same data
format, same CLI.

## The glaze host

Production transport is the native GLZ1 carrier on the controlled
`glaze://` origin — no loopback TCP port exists. `TASKLY_TRANSPORT=http`
selects the explicit dev/CI adapter (loopback server, token-guarded, SSE
push at `/glaze/events`); the packaged CI smoke and the real-window
verifier exercise it.

The packaged binary embeds Racket CS through `raco exe`/glaze build: the
engine backend is a **static** require of the adapter so the distribution
contains every module (a runtime `dynamic-require` cannot resolve source
paths inside a packaged tree). The thin host adds tray, global quick-add
hotkey, a second `#capture` window that never opens the database, OS
autostart (installed-build guarded) and close-to-tray.

Historical note: the pre-rewrite Windows section diagrammed a reversible
C#/WinUI backend boundary (`ITasklyBackend`, `UseRivetBackend=true`); that
implementation no longer exists. What still holds from it: the release
target is **not** a hidden Racket child process — Racket CS lives in the
Taskly process on every platform.

## Repository layout

```text
taskly/
├── racket/
│   ├── taskly/
│   │   ├── model.rkt
│   │   ├── errors.rkt
│   │   ├── clock.rkt
│   │   ├── paths.rkt
│   │   ├── config.rkt
│   │   ├── validation.rkt
│   │   ├── date-parser.rkt
│   │   ├── reminder.rkt     # reminder decisions + delivery acknowledgement state
│   │   ├── db.rkt
│   │   ├── service.rkt
│   │   ├── rivet-schema.rkt
│   │   ├── backend.rkt      # Rivet backend entry (typed RPC surface)
│   │   ├── cli.rkt          # agent CLI (taskly list|add|…)
│   │   ├── updater.rkt      # update feed client (shared/spec/UPDATE.md)
│   │   └── version.rkt
│   └── tests/
│       ├── core-test.rkt
│       ├── backend-test.rkt
│       ├── backend-wire-test.rkt
│       ├── rivet-schema-test.rkt
│       ├── updater-test.rkt
│       └── cli-update-test.rkt
├── backend/           # glaze adapter: typed routes, RVT1 pipes, thin host, e2e gate
│   └── tests/         # adapter contract test (headless, every platform)
├── apps/desktop/      # the single web UI (Vite + TS) + in-page acceptance harness
├── packages/core/     # generated rpc.ts + dual-transport bridge
├── shared/            # spec contracts, i18n, emoji, cli-golden
├── scripts/           # codegen, surface gates, release tooling, acceptance runner
├── assets/            # icons and branding
├── flatpak/           # Linux Flatpak packaging (glaze payload)
├── docs/              # user guides + handoff/benchmark notes
├── site/              # GitHub Pages product site
├── rivet.rktd         # release identity metadata
├── rivet-schema.json  # RPC contract (unchanged by the host rewrite)
├── glaze-schema.json  # generated typed-route baseline
├── rivet-acceptance.rktd  # executable acceptance contract
└── verify.rkt         # real-window smoke + §6 journey verdicts
```

## Compatibility invariants

The host rewrite does not define a new product format.

- `PRAGMA user_version = 4`
- existing `.db` files open in-place
- WAL remains enabled
- default list remains `工作` / `📋` / signed ARGB `0xFF007AFF`
- task/list storage formats remain those in `shared/spec/DATA-FORMAT.md`
- CLI meanings and exit codes remain those in `shared/spec/CLI-SPEC.md`
- visual behavior remains measured against `design/prototype/` (single web
  host; the old cross-host token parity gate retired with the native hosts)

## Rivet / glaze dependency rule

Taskly is allowed to reveal missing framework capabilities. It is not
allowed to work around reusable host/runtime problems inside Taskly.

Capabilities Taskly has already driven upstream:

1. named Record/DTO schema types layered compatibly on RVT1 (rivet)
2. strict protocol-channel behavior (backend declarations may not pollute stdout)
3. release machinery this product consumes directly: signed update
   manifests (rivet format, `raco rivet sign-manifest`), platform packaging
4. glaze typed-route schema baselines, event bus push, tray/hotkey/autostart
   surfaces used by the thin host

Open upstream gaps driven by this rewrite: glaze#140 (Windows capture
vertical flip), glaze#141 (tray on-event dead parameter / left click /
TaskbarCreated). Remaining framework/product gaps include richer typed
remote errors/diagnostics and production crash/lifecycle instrumentation.

RVT1 remains protocol version 1. Records are schema/codegen constructs
encoded as field-ordered RVT1 lists, so typed DTO support did not require a
transport version break. (An early .NET client path — C# codegen,
`rivet_native.dll`, `raco rivet build-dotnet` — existed during the migration
and was dropped when the Windows host settled on C++/WinRT; see the rivet
PR #50/#51 discussion. The generated Swift/C++ clients retired with the
native hosts; `packages/core/src/rpc.ts` is the single generated client.)

## Migration safety

The host stays presentation-only: product behavior lives in the Racket
core. Do not build a general-purpose declarative UI toolkit before Taskly
needs one. If repeated UI patterns justify an abstraction later, extract
the smallest reusable primitive from real Taskly code.

Missing rivet/glaze capabilities surface as upstream issues/PRs against
`turlamai/rivet` / `turlamai/glaze` as product work hits them; the
historical backlog of taskly-driven framework work (and its resolution
record) is in git history and the upstream issue trackers.