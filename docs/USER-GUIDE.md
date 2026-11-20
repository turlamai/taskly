# Taskly user guide

**English** · [简体中文](USER-GUIDE.zh-CN.md)

A local task manager for lists, quick capture and scheduled reminders.

## Availability

Development preview; no paid checkout is open. A future official desktop purchase will be announced with its delivered terms.

## Platforms and installation

Desktop previews for macOS, Windows and Linux. Select the OS and CPU shown on the release asset; mobile and watch applications are not delivered products.

Use [official Releases](https://github.com/turlamai/taskly/releases), select an explicitly listed OS/architecture asset, read its release notes and check supplied checksums. An absent asset/platform is not a delivery promise. Preview builds may lack publisher signing or notarization; do not disable system-wide security protections to install them.

- Windows: use the x64 MSI for Start-menu and Apps & Features integration, or the ZIP for a portable copy. Current preview MSI files are not Authenticode-signed, so publisher trust and SmartScreen reputation are not production-ready.
- macOS: open the DMG and drag Taskly to Applications. Current previews are ad-hoc signed rather than Developer ID signed/notarized; a Gatekeeper rejection is not a prompt to disable Gatekeeper.
- Linux: use deb on Debian/Ubuntu, rpm on Fedora-compatible systems, AppImage for a portable launch, or the Flatpak bundle (`flatpak --user install ./taskly-<version>-linux-<arch>.flatpak`; the bundle carries the app payload only and pulls the GNOME Platform runtime from your Flatpak remote on first install). The packages install a desktop entry and icon; use the same package manager (or `flatpak --user update`) for upgrades and removal.

## Your first successful session

1. The default list is ready on first launch. Add one non-sensitive task in the field above the empty-state hint; no setup wizard or list creation is required.
2. Open the task, choose a date, then use the visible Save action. Quit and reopen Taskly and confirm the task and date persisted.
3. Reminders: the reminder field persists, but OS notification delivery is staged (#131) — do not expect banners yet, in any state.

## Data, backup and recovery

Tasks use SQLite, normally ~/.taskly/tasks.db, with configuration in ~/.taskly/config.ini. Quit every Taskly process, then back up the directory, including any WAL/SHM files. Restore into a separate copy first. A cloud-synced live database is not a supported concurrent-editing mechanism.

## Keyboard and editing

Ctrl/⌘+K focuses search. In the task list, Enter (or the edit action) opens inline editing; the editor always shows Save and Cancel. Enter saves, Escape or Cancel discards the whole draft, and clicking outside the editor commits it. The date chip cycles none → today → tomorrow; arbitrary dates and times live in the details popover's date/time fields. Choosing a date in the editor only changes the draft: Save, Enter or clicking another row persists it, with saving/success/error feedback. A failed explicit save keeps the draft available for retry. Delete is staged for about six seconds; Undo restores the same task identity and metadata. Multi-select, batch actions, arrow-key row navigation and the Ctrl/⌘+1…4 / N / F / ⇧C accelerators are benchmark targets not yet in this host (see UX-BENCHMARKS).

The ⓘ button on a task row opens the task details popover on every platform: completion, title, date, time, priority, tags, subtasks, notes, URL and list membership in one layer. Every change saves as it is made — closing never discards — and a failed save anchors an actionable error to its field. Clicking the task title still opens the inline editor.

## Network, keys and privacy

Core task use is local. Update checks/downloads and links you open contact external services. Sharing a database or diagnostics can disclose task titles and notes.

## Known limits

Reminder eligibility is evaluated consistently by the shared core on every platform, but OS notification delivery is staged (#131): fields persist, nothing fires yet. The standalone packaged CLI is not yet part of desktop releases; source CLI instructions remain in the README.

## Updates and removal

Back up data and read the destination release notes first. Taskly checks silently shortly after launch (at most once every four hours) and lets you check manually from Settings on every platform. macOS, Windows MSI/portable, Linux AppImage and portable tarballs install the verified update in place; deb/rpm and Flatpak copies are directed to the system package manager (or `flatpak --user update`), which owns the upgrade. Never bypass a failed signature check or replace the program with an untrusted artifact. On failure, preserve data and the error, then recover with a trusted release. Removing the program does not necessarily erase its separate data directory; verify your backup before deleting personal data.

DMG, MSI, deb/rpm and portable archives replace application files, not `~/.taskly/`. If an update fails, quit all Taskly processes and reinstall the previous trusted build using the same installation shape; portable users can return to the previous program directory. The exact per-shape rollback table is in the update contract below.

Remove the Windows MSI from Apps & Features, delete the macOS application from Applications, or remove the Linux package with the package manager that installed it. AppImage and ZIP copies are removed by deleting their application file/folder. These operations intentionally preserve `~/.taskly/`; deleting personal data is a separate, explicit action after backup.

## Get help

Report problems in [GitHub Issues](https://github.com/turlamai/taskly/issues), in English or Chinese. Include the version, OS/architecture, installation channel, steps, expected result and actual result. Reproduce with synthetic input first; do not attach keys, credentials, databases, private source documents or complete logs. Public support has no guaranteed response time.

## Further reading

- [Detailed manual](../site/manual.html)
- [Data format](../shared/spec/DATA-FORMAT.md)
- [Update contract](../shared/spec/UPDATE.md)
- [Project overview and development](../README.md)
- [Current licence](../LICENSE)
