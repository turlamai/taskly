# Taskly Design Tokens (Contract)

> Taskly's visual language is warm, quiet and content-first: a terracotta
> action accent, warm neutral surfaces and generous whitespace. Webview
> typography and controls stay intact; Things, TickTick and Reminders are
> interaction references rather than pixel templates. The single glaze web
> host consumes these values directly from the prototype CSS; smart-tile
> colors remain theme-independent.

**v0.2 baseline (2026-11-12, prototype polish, issue #130).** Values have a
single home: `design/prototype/shared.css`. Since the glaze rewrite
(issue #141) the web UI `@import`s that file (plus `database-flow.css`)
unchanged, so there is exactly one implementation and no cross-host parity
gate: light tertiary darkened `#767370 → #6B6866`
(4.9:1, safe at 12px); dark secondary lifted `#B2AEAC → #C3BFBD`; danger and
planned become
light/dark pairs; new semantic tokens (divider-strong, accent-ink,
today-ink, warn-ink, success, tag fills, scrim, shadow scale, motion, focus
ring); the list palette is semanticized with dark variants; a second editing
surface — the anchored task-detail popover with per-field autosave — joins
the inline quick editor.

## Semantic colors (names only; canonical values in shared.css)

| Token | CSS vars | Use |
|---|---|---|
| `accent/action` | `--accent` | Primary actions, switches, accent fills |
| `accent-ink` | `--accent-ink` | Text/icon on accent fills |
| `accent/today` | `--today` | Today tile, default list color, focus ring |
| `today-ink` | `--today-ink` | Today numerals, due-today text |
| `tile/planned` | `--planned` | Planned tile glyph |
| `tile/all` | `--gray-tile` | All / Completed tiles |
| `danger` | `--danger` | Destructive actions, overdue text, high priority |
| `warn-ink` | `--warn-ink` | Medium priority |
| `success` | `--success` | Status confirmation |

`flag` is retired in v0.2 (superseded by `list-orange`).

## Theme values (canonical in shared.css — never duplicated here)

Light and dark values for surfaces (`--bg --sidebar --surface --divider
--divider-strong`), text tiers (`--ink --ink2 --ink3`), alpha interaction
fills (`--sel --hover`), inputs (`--input-border`), badges (`--badge-bg
--badge-text`), tags (`--tag-bg --tag-text`) and the scrim (`--scrim`) live
in `design/prototype/shared.css`. Contrast floors (4.5:1 for text tiers and
accents, 3:1 for input borders) are computed by the checker from the parsed
CSS values. Dark keeps layered grays, never pure black.

## System tokens (v0.2)

| Token | Value |
|---|---|
| focus ring | `:focus-visible` = 2px `accent/today` outline, offset 2 (offset 1 on inputs) |
| shadow-1 | light `0 1px 2px rgba(29,29,31,.10)` · dark `0 1px 2px rgba(0,0,0,.30)` |
| shadow-2 | light `0 12px 32px rgba(29,29,31,.16), 0 32px 80px rgba(29,29,31,.20)` · dark `0 12px 32px rgba(0,0,0,.45), 0 32px 80px rgba(0,0,0,.55)` |
| motion | fast 140ms · base 200ms · exit 120ms; ease-out `cubic-bezier(.2,.8,.2,1)`, ease-in `cubic-bezier(.4,0,1,1)` |
| reduced motion | `prefers-reduced-motion: reduce` disables all transitions and animations |
| theme system | `light` / `dark` / `system` (persisted); applied before first paint (no flash); system appearance changes tracked live |
| a11y | row/nav state via `aria-current` / `aria-pressed` / `aria-checked` / `aria-expanded`; task changes announced through an `aria-live` region |

## List palette (12 semantic colors, fixed order)

Tasks store the semantic name, never the hex — theme switching re-maps
automatically. iOS system colors, light/dark paired:

| Name | CSS var |
|---|---|
| `blue` | `--list-blue` |
| `red` | `--list-red` |
| `orange` | `--list-orange` |
| `yellow` | `--list-yellow` |
| `green` | `--list-green` |
| `cyan` | `--list-cyan` |
| `indigo` | `--list-indigo` |
| `pink` | `--list-pink` |
| `gray` | `--list-gray` |
| `silver` | `--list-silver` |
| `brown` | `--list-brown` |
| `teal` | `--list-teal` |

## Emoji catalog (single source: `shared/emoji.json`)

8 categories × 12 emoji, synced to all platforms by `scripts/sync-i18n.sh`
(the data file is `shared/emoji.json`; category display names live in the
i18n tables as `emojiCat_<id>`). Windows 10 font-safe emoji only.
Categories in order: frequent · people · nature · food · activity ·
travel · objects · symbols.

## List editor picker contract

List editing shows a **tabbed category grid** for the icon and a **swatch
row/grid** for the color — the same catalog, category order and palette on
every platform. Never a text dropdown of hex values.

## Geometry & type

| Token | Value |
|---|---|
| window default | 1280×880 (min 760×520 logical) |
| sidebar collapse | toggle sets the column width to 0 (releasing MinWidth) — a fixed MinWidth must not clamp the collapsed state |
| sidebar width | 280 (200…420) |
| menu bar / status bar height | 32 / 28 |
| smart-list chip | 2×2 grid of 34px chips (radius 8, 8px gaps): neutral surface fill + 1px divider, horizontal content = colored glyph (14px, view semantic color) + 13px label + quiet 12px count right; checked = quiet selection fill (VSM), hover = hover fill; saturated color never fills the chip — color lives on the glyph (macOS Reminders language) |
| list row | card: surface fill + 1px divider border, radius 8, padding 8,5; 20px round color dot with the emoji inside (11px), name 13px, gray count right — compact, aligned with the sidebar icon column |
| list icon size | 32 (round) |
| checkbox size | 20px ring in the task's list color (accent fallback), resting ring mixed 82% toward ink for definition; completed = list-color fill with a white check |
| task row | 44px min height, padding 16,9; text 14px; meta 12px with the owning list name (list-colored dot + name) shown in multi-list views, clickable tag chips (filter), priority glyphs (!/!!/!!!), subtask count; info button at 65% opacity, full on row hover/focus or when its popover is open |
| corner radius (rows/cards) | 8 / 10 / 12 |
| content padding | 16, 8; sidebar item 12, 10 |
| task text | 14px; list name 13px |
| view header | large title 22px semibold (view name) + 13px secondary subtitle line beneath (today view → full weekday date, calendar → month with task count, list/all → N open tasks); the show-completed toggle stays top-right |
| due-date semantics | due dates render localized (今天/明天/昨天/8月31日); overdue incomplete → `--danger`, due today → `--today-ink`, otherwise text/secondary; a leading clock glyph only when a time is set |
| input fields | search 30px, quick add 36px, radius 10, 1px input-border |
| font stack | system UI font of the platform (`-apple-system` / Segoe UI / GNOME default), CJK fallback PingFang SC / Microsoft YaHei / Noto Sans CJK SC |

Tile glyphs are monochrome platform icon fonts (Windows: Segoe Fluent Icons;
macOS: SF Symbols; Linux: symbolic icons), not emoji — mixed emoji/text runs
render fallback debris on some stacks.

## Inline quick editor (Things/Reminders style)

The selected row expands in place for a quick edit. The task text remains
the visual title (15px semibold, borderless, up to three lines). Notes use
a 13px borderless multiline field with a tertiary placeholder. Date and
time render as compact rounded chips in the single web host (the old
GTK/WinUI grouped-field fallback retired with the native hosts). The quick editor
does not introduce a second card or dialog border. PRODUCT-SPEC §5/§6 owns
the shared Enter-save, Escape-cancel and click-away-save behavior.

## Anchored task detail layer (v0.2)

The full-field editor is an **anchored popover** (`role="dialog"`,
`aria-modal="false"`), 348px wide (max `100% - 24px`), anchored to the
row's right edge with a 16px inset, vertically clamped inside the pane,
shadow-2 elevation. It opens from the row's `ⓘ` button
(`aria-haspopup="dialog"`, `aria-expanded` tracked) and carries: completion
checkbox, title, date, time, reminder, priority segmented control, tags,
subtasks, notes, URL and list membership.

**Persistence is per-field autosave** — every change persists as it is
made; there is no draft and closing never discards. Visible actions are
删除 (destructive, ~6s undo per PRODUCT-SPEC §5b) and 完成 (close).
Clicking outside closes. If a change fails to persist, an actionable error
anchors to that field and the popover stays open for retry. The popover
closes when its task leaves the current view.

## App icon

White rounded square (macOS-squircle radius ≈ 22.5%) with a quiet checklist
mark: one terracotta rounded bar over two neutral (`#CECED3`) bars, staggered
widths. Monochrome, no gradients — must read on light and dark docks alike.

## Installer artwork (native-host contracts retired, issue #141)

The WiX wizard bitmap contract and the branded macOS DMG background contract
lived with the three native hosts and are retired with them (slice 4). The
glaze installer chain consumes the brand assets directly: `assets/taskly.ico`
(Windows MSI/NSIS + tray) and `assets/taskly.icns` (macOS bundle); the DMG is
the plain drag-to-Applications volume (family glaze-line pattern). The retired
artwork sources (`wizard-*`, `dmg-background.*`) and their pixel gates
(`scripts/check-windows-installer-bitmaps.py`, `scripts/render-dmg-background.sh`)
are deleted; history stays in git.

## Host mapping (single glaze web host)

The contract above is consumed at one fixed location. When changing a token
value: change `design/prototype/shared.css` (or `database-flow.css`) — the web
UI imports both unchanged, so every surface follows in the same commit.

| Host | Colors | Theme switching | Geometry/type |
|---|---|---|---|
| glaze web UI — `apps/desktop/src/style.css` `@import`s `design/prototype/shared.css` + `database-flow.css` | the prototype's semantic custom properties, verbatim | `prefers-color-scheme` + persisted `data-theme` override applied before first paint (`src/theme.ts`) | prototype geometry verbatim (sidebar 280, search 30, quick-add 36/r10, detail layer per §Anchored task detail layer) |

Tile glyphs stay monochrome (emoji catalog from `shared/emoji.json`, rendered
as text glyphs in the web list tiles).

## Drift ledger (retired with the native hosts, issue #141)

D1–D13 (recorded 2026-11-11 by the design-gate slice, issue #121) tracked spec
vs. the three native hosts. With a single web host importing the prototype CSS
there is no cross-host drift surface left; the ledger and its gate
(`scripts/check-design-tokens.py`) are retired in slice 4. The full table stays
readable in git history.

## Prototype-first process (this repo)

- The visual contract is **this file** plus the prototype CSS it points at.
  Prototypes live in `design/prototype/` and render this contract as
  reviewable HTML before UI code changes: contract change → prototype update
  → review → then the web host (which imports the prototype directly).
- Design-gate exit: key screens prototyped, interaction logic locked against
  PRODUCT-SPEC.
- Platform-native idioms stay (PRODUCT-SPEC header): prototypes express
  intent, not pixel templates — a host-specific exception must be written
  into PRODUCT-SPEC before implementation, never discovered in review.
