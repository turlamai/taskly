# Taskly Design Tokens (Contract)

> Taskly's visual language is warm, quiet and content-first: a terracotta
> action accent, warm neutral surfaces and generous whitespace. Platform-native
> typography and controls stay intact; Things, TickTick and Reminders are
> interaction references rather than pixel templates. Every platform
> implements these values as named constants; smart-tile colors remain
> theme-independent.

## Semantic colors (theme-independent)

| Token | Hex | Use |
|---|---|---|
| `accent/today` | `#007AFF` | Today tile, default list color, light-mode accent |
| `accent/today-dark` | `#0A84FF` | Dark-mode accent |
| `tile/planned` | `#FF3B30` | Planned tile |
| `tile/all` | `#8E8E93` | All tile |
| `tile/completed` | `#8E8E93` | Completed tile |
| `flag` (reserved) | `#FF9500` | Flagged (unused) |
| `danger` | `#FF3B30` | Destructive buttons |
| `accent/action` | `#C94F30` | Primary actions and focus, light mode |
| `accent/action-dark` | `#E8704F` | Primary actions and focus, dark mode |

## Light theme

| Token | Hex |
|---|---|
| `background` | `#FFFFFF` |
| `sidebar` | `#F3F2F1` |
| `surface` | `#FFFFFF` |
| `divider` | `#E1DFDD` |
| `text/primary` | `#1D1D1F` |
| `text/secondary` | `#5F5D5B` |
| `text/tertiary` | `#767370` |
| `selection` | `#14000000` (black @ 8%) |
| `hover` | `#0D000000` (black @ 5%) |
| `input-border` | `#8A8785` |
| `badge/background` | `#E9E9EE` |
| `badge/text` | `#58585D` |

## Dark theme (layered grays, never pure black)

| Token | Hex |
|---|---|
| `background` | `#1E1E1E` |
| `sidebar` | `#272424` (one step lighter than content) |
| `surface` | `#323234` |
| `divider` | `#3B3939` |
| `text/primary` | `#F5F5F7` |
| `text/secondary` | `#B2AEAC` |
| `text/tertiary` | `#A8A5A3` |
| `selection` | `#1FFFFFFF` (white @ 12%) |
| `hover` | `#12FFFFFF` (white @ 7%) |
| `input-border` | `#777371` |
| `badge/background` | `#3F3F44` |
| `badge/text` | `#E9E9EE` |

## List-palette presets (fixed order, iOS system colors)

`#007AFF` `#FF3B30` `#FF9500` `#FFCC00` `#4CD964` `#5AC8FA` `#5856D6`
`#FF2D55` `#8E8E93` `#C7C7CC` `#A2845E` `#00C7BE`

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
| checkbox size | 20px ring in the task's list color (accent fallback); completed = list-color fill with a white check |
| task row | 44px min height, padding 16,9; text 14px; meta 12px with the owning list name (list-colored dot + name) shown in multi-list views; info button at 45% opacity, full on row hover |
| corner radius (rows/cards) | 8 / 10 / 12 |
| content padding | 16, 8; sidebar item 12, 10 |
| task text | 14px; list name 13px |
| view header | large title 22px semibold (view name) + 13px secondary subtitle line beneath (today view → full weekday date, calendar → month with task count, list/all → N open tasks); the show-completed toggle stays top-right |
| due-date semantics | due dates render localized (今天/明天/昨天/8月31日); overdue incomplete → `#FF3B30`, due today → accent, otherwise text/secondary; a leading clock glyph only when a time is set |
| input fields | search 30px, quick add 36px, radius 10, 1px input-border |
| font stack | system UI font of the platform (`-apple-system` / Segoe UI / GNOME default), CJK fallback PingFang SC / Microsoft YaHei / Noto Sans CJK SC |

Tile glyphs are monochrome platform icon fonts (Windows: Segoe Fluent Icons;
macOS: SF Symbols; Linux: symbolic icons), not emoji — mixed emoji/text runs
render fallback debris on some stacks.

## Inline task editor (Things/Reminders style)

The selected row expands in place; there is no task-detail modal. The task
text remains the visual title (15px semibold, borderless, up to three lines).
Notes use a 13px borderless multiline field with a tertiary placeholder.
Date and time render as compact rounded chips where the native toolkit
supports them, or equivalently grouped native fields on GTK/WinUI. The editor
does not introduce a second card or dialog border. PRODUCT-SPEC §5/§6 owns
the shared Enter-save, Escape-cancel and click-away-save behavior.

## App icon

White rounded square (macOS-squircle radius ≈ 22.5%) with a quiet checklist
mark: one terracotta rounded bar over two neutral (`#CECED3`) bars, staggered
widths. Monochrome, no gradients — must read on light and dark docks alike.

## Windows MSI installer artwork

WiX 5's `WixUI_InstallDir` shares `assets/wizard-dialog.bmp` (493×312)
between welcome and completion pages. Its `ExitDialog` optional checkbox is
**opaque** at x=135…355 and y=190…230 installer units, mapping to approximately
x=180…473 and y=253…307 on the bitmap. Gradients under this native control
produce a conspicuous rectangular patch.

The image's **entire bottom footer** (y=248…311) is flat classic Windows
button-face `#F0F0F0`, with a subtle divider at y=247. The interactive
checkbox remains native and accessible, while its backing now blends into the
same surface. Keep SVG, PNG preview, and shipping BMP synchronized.
`scripts/check-windows-installer-bitmaps.py` verifies pixel identity and
native checkbox surface in CI, packaged acceptance and Windows release.

## macOS DMG artwork contract

- The editable source is `assets/dmg-background.svg`; the shipping installer
  embeds `assets/dmg-background.png`, regenerated before macOS release and
  packaged acceptance by `scripts/render-dmg-background.sh` (`librsvg`).
- Finder's branded installer is 660×400 points at 2× scale, requiring a
  1320×800 background. The Taskly and Applications icon slots are controlled
  by pinned Rivet (positions 130,160 and 450,160 at 80pt icons). Keep the
  straight drag arrow centered in the clear space between those slots and
  do not draw art over the icon/label areas. The small `DRAG TO INSTALL`
  cue and high-contrast bottom instruction sit entirely in the background's
  clear middle and lower text zones, never underneath Finder's icon labels.
- Final visual acceptance must inspect the mounted DMG in Finder (not only the
  raw SVG/PNG): app icon, Applications target, arrowhead and labels must stay
  aligned at native scale. The 1320x800 renderer check is necessary but cannot
  prove Finder's overlay composition is correct.

## Platform mapping table (where tokens live in each host)

The contract above is consumed at fixed, CI-checked locations. When changing
a token value: change it here first, then in all three hosts —
`scripts/check-design-tokens.py` gates the shared hexes in CI (coverage gap:
see drift D9).

| Host | Colors | Theme switching | Geometry/type |
|---|---|---|---|
| macOS — `macos-host/Sources/RivetHost/Theme.swift` | `Palette` code constants (this file is cited in the file header); dual light/dark constants with `ThemeState.isDark` ternaries; list palette `listColorsHex` | KVO on `NSApplication.effectiveAppearance`; settings override via `NSApp.appearance` (`nil` = system) | sidebar 280 / status 28 / chip 34; window `.defaultSize(1280×880)`, min 760×520 |
| Windows — `windows/MainWindow.xaml` `ResourceDictionary.ThemeDictionaries` | Light/Dark dictionaries: `TasklyAccentBrush`, `TasklySidebarBrush`, `TasklySurfaceBrush`, `TasklyDividerBrush`, `TasklySelectionBrush`, `TasklyHoverBrush`, secondary/muted text brushes; theme-independent tile brushes below the dictionaries | `RootGrid().RequestedTheme` via `MainWindow::ApplyTheme`; `ActualThemeChanged` re-applies brushes to hand-built rows | sidebar 280 (200–420); search 28 (spec 30 — D5); quick-add 40/12 (spec 36/10 — D6) |
| Linux — `linux/src/main.cpp` `Palette`/`kLight`/`kDark` + `apply_css` | constexpr palette mirroring Theme.swift (incl. alpha selection/hover); CSS assembled as strings at runtime, no .css file | GSettings `color-scheme prefer-dark`, libadwaita fallback theme-name sniff; forcing light on a dark system is an accepted delta without libadwaita | sidebar 200–420 via paned handle; menu bar 30 (spec 32 — D7); default window 1000×680 (see D1) |

Tile glyphs stay monochrome platform icon fonts (SF Symbols / Segoe Fluent
Icons / symbolic icons) on every host.

## Drift ledger (spec vs hosts, recorded 2026-11-11)

Recorded by the design-gate slice (issue #121). Each item is fixed by an
implementation slice or resolved by an explicit spec amendment — never
silently pick a side:

| # | Item | Spec | Reality | Resolution owner |
|---|---|---|---|---|
| D1 | Window default size | DESIGN-TOKENS says 1280×880, PRODUCT-SPEC §2 says 1024×768 — the specs contradict each other | macOS 1280×880 · Windows 1024×768 · Linux 1000×680 | spec owners pick one value; all legs align |
| D2 | Windows due-today color | = action accent | ~~`#C4501B`/`#F2913D`~~ | ✅ fixed on leg/win-drift |
| D3 | Windows overdue color | `#FF3B30` | ~~`#D13438`/`#FF6B6E`~~ | ✅ fixed on leg/win-drift |
| D4 | Windows hover/selection fills | alpha fills (hover 5%/7%, selection 8%/12%) | ~~opaque approximations~~ | ✅ fixed on leg/win-drift |
| D5 | Search box height | 30px | ~~Windows 28~~ | ✅ fixed on leg/win-drift |
| D6 | Quick-add field | 36px, radius 10 | Windows 40/r12 ✅ fixed · Linux 38/r12 outstanding | Windows ✅ / Linux leg slice |
| D7 | Menu bar height | 32 | Linux 30 | Linux leg slice |
| D8 | List editor picker | tabbed 8×12 emoji grid + 12-swatch row, same on every platform | macOS complete · Linux legacy flat 16 emojis, ignores `shared/emoji.json` · **Windows has no picker at all** (plain text prompt) | one leg slice per platform; Windows is the outright contract violation |
| D9 | Token CI coverage | every shared hex gated on every host | ~~only 6 values on Windows~~ | ✅ extended on leg/win-drift |
| D10 | Completed checkbox | this file: list-color fill + white check; PRODUCT-SPEC §5: "ring + check in accent" — the specs contradict | legs vary | spec owners pick one; prototype renders this file's version |

## Prototype-first process (this repo)

- The visual contract is **this file** (single source — Theme.swift cites it
  in its header). Prototypes live in `design/prototype/` and render this
  contract as reviewable HTML before any host code changes: contract change →
  prototype update → review → then the legs.
- Design-gate exit: key screens prototyped, interaction logic locked against
  PRODUCT-SPEC, drift ledger dispositioned.
- Platform-native idioms stay (PRODUCT-SPEC header): prototypes express
  intent, not pixel templates — a host-specific exception must be written
  into PRODUCT-SPEC before implementation, never discovered in review.
