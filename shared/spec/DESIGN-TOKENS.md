# Taskly Design Tokens (Contract)

> Taskly's visual language is warm, quiet and content-first: a terracotta
> action accent, warm neutral surfaces and generous whitespace. Platform-native
> typography and controls stay intact; Things, TickTick and Reminders are
> interaction references rather than pixel templates. Every platform
> implements these values as named constants; smart-tile colors remain
> theme-independent.

**v0.2 baseline (2026-11-12, prototype polish, issue #130).** Values have a
single home: `design/prototype/shared.css`. `scripts/check-design-tokens.py`
parses the CSS and gates the three hosts against it — hosts aligned in the
same atomic slice (drift D11 ✅): light tertiary darkened `#767370 → #6B6866`
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
time render as compact rounded chips where the native toolkit supports
them, or equivalently grouped native fields on GTK/WinUI. The quick editor
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
| D1 | Window default size | ~~DESIGN-TOKENS says 1280×880, PRODUCT-SPEC §2 says 1024×768~~ | all legs 1280×880 ✅ (Windows/Linux aligned on leg/linux-win-align) | ✅ resolved: spec amended + legs aligned |
| D2 | Windows due-today color | = action accent | ~~`TasklyDueTodayBrush #C4501B` / dark `#F2913D`~~ | ✅ fixed on leg/win-drift-2 |
| D3 | Windows overdue color | `#FF3B30` | ~~`#D13438` / dark `#FF6B6E`~~ | ✅ fixed on leg/win-drift-2 |
| D4 | Windows hover/selection fills | alpha fills (hover 5%/7%, selection 8%/12%) | ~~opaque approximations `#EBE9E7`/`#332F2F` and `#E8E4E0`/`#3A3736`~~ | ✅ fixed on leg/win-drift-2 |
| D5 | Search box height | 30px | ~~Windows 28~~ | ✅ fixed on leg/win-drift-2 |
| D6 | Quick-add field | 36px, radius 10 | ~~Windows 40/r12 · Linux 38/r12~~ | ✅ fixed on leg/win-drift + leg/linux-win-align |
| D7 | Menu bar height | 32 | ~~Linux 30~~ | ✅ fixed on leg/linux-win-align |
| D8 | List editor picker | tabbed 8×12 emoji grid + 12-swatch row, same on every platform | macOS complete · Linux ✅ upgraded to shared/emoji.json tabbed grid · **Windows has no picker at all** (plain text prompt) | Windows leg slice — the remaining contract violation |
| D9 | Token CI coverage | every shared hex gated on every host | ~~only 6 values on Windows~~ | ✅ extended on leg/win-drift-2 |
| D10 | Completed checkbox | ~~PRODUCT-SPEC §5: "ring + check in accent"~~ | leg audit 2026-11-11: macOS compliant · Linux declared exception (§5 8px dot) · **Windows stock CheckBox = undeclared drift** | ✅ spec amended; Windows leg slice: implement the 20px list-color ring or declare the exception in §5 first |
| D11 | Token values v0.2 on hosts (issue #130) | light tertiary `#6B6866`, dark secondary `#C3BFBD`, checker derives all gated values from shared.css | ~~hosts + checker at v0.1 values~~ | ✅ resolved: atomic slice aligned Theme.swift + MainWindow.xaml + main.cpp + checker (checker now parses shared.css, no value dict) |
| D12 | Overdue color on hosts | `danger` pair (see D11) | ~~theme-independent `#FF3B30` overdue brush/text on all three legs~~ | ✅ resolved: atomic slice migrated Theme.swift (`lightDanger`/`darkDanger` + `ThemeState.danger`), Windows `TasklyOverdueBrush` and Linux `Palette.overdue` to the parsed `--danger` pair; checker gates all legs |
| D13 | Detail layer on hosts | anchored task-detail popover with per-field autosave (§Anchored task detail layer) + theme system (persisted light/dark/system, boot-before-paint) | ~~hosts implement the inline quick editor only~~ | ✅ resolved on all three legs in 0.2.12 (macOS TaskDetailPopover `c6f8f63`; Windows Flyout + Linux overlay panel `ba9000c`; acceptance traces green on all CI legs + Ubuntu VM). Reminder offsets staged (A2, #131) |

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
