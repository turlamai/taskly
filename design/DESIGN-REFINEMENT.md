# Taskly prototype refinement

> **Host-generation note (2026-11-20, issue #141):** the product host is now
> the single glaze web UI. Where this document contrasts browser-prototype
> limits with "native" behavior, read "native" as the thin-host capabilities
> the glaze adapter provides (pickers, tray, hotkey, autostart); the
> prototype's CSS/IA is the web host's visual single source.

## Scope

This iteration retains the existing compact neutral design, semantic colors, and light/dark themes. It changes the HTML prototype only; the upstream product and token specifications referenced by DESIGN.md are not modified here.

## Task details

Both the main window and the standalone detail review page expose title, date, notes, and list membership directly. Time/reminder, priority, tags, subtasks, and URL use keyboard-accessible native disclosure controls. A section opens on task selection when it already contains a value. Empty sections remain available without presenting an empty form by default. Existing live-update task handlers and field identifiers are preserved.

## Navigation

The index opens the main application window directly. No screen directory or review launcher is retained. Main and detail sidebars link to settings; settings links back to the main window. New-list creation remains next to the list section.

## Settings

- General: language preference and theme. Language is recorded only; prototype text is not translated.
- New tasks: the same four default lists as the main window, plus shortcut recording. The main window reads the default-list preference when adding outside a selected list. Shortcuts are not registered with the operating system.
- Data: a labeled simulation of database creation, opening, folder reveal, migration, JSON export, and backup restoration. The previous speculative automatic-update modes are removed.

## Database lifecycle

The main window now starts with a database gate if there is no selected database. The user chooses Create or Open. Creation requires an explicitly entered folder and database name, uses taskly.sqlite as the proposed filename, and opens an empty task list. No default storage folder or populated task set is silently assigned. Opening an existing location restores the corresponding prototype record if registered, or opens a new empty simulated record without reading the real file.

The prototype keeps a registry of database identities, positions, and task snapshots in browser storage. Each database has an independent snapshot. Switching databases preserves the previous database's tasks; startup reopens the selected record when browser storage is available. The registry is prototype metadata, not an implementation decision about the actual product's SQLite schema.

Settings shows the current name and file location, and offers folder reveal, migration, opening another database, and creation. Reveal explains that a native host would open the system file manager; this browser prototype cannot do so. Migration first collects a target and then requires confirmation. It changes the current record's location only on success. Known target collisions are rejected, and cancellation never modifies the active record. JSON import/export operates only on the selected database; restoring requires confirmation and cannot overwrite a different selected database if the selection changes.

Failure specimens are direct query-string entries on the relevant page, outside product UI. Query specimens create-failed, open-failed, and migrate-failed produce one simulated failure on submission, then permit retry. The missing specimen blocks opening the selected database, preserves its task snapshot, and offers retry, relocation, opening another database, or explicit creation. It never creates a replacement automatically. Missing and migration specimens require an existing prototype record for the full recovery flow. A simulated relocation assumes the user selected the original file; real implementation must verify database identity before restoring that association.

No SQLite header checks, filesystem access, directory creation, file migration, or cloud synchronization occur here. Native creation must be exclusive and atomic, reject an existing target, check access, and open the main UI only after successful initialization. Native migration must preserve the source on failure; file identity, durability, backups, and multi-device synchronization require implementation and verification beyond this prototype.

## Data boundary

The SQLite-backed product remains the intended real application. This HTML prototype does not open, move, back up, or synchronize an actual database. Creating, opening, relocating, or migrating a displayed database changes prototype registry records only. No synchronization provider is selected or configured.

When browser storage is available, the main window stores each selected database’s task snapshot locally. Export downloads that snapshot as a taskly-prototype version 1 JSON file, including every main-window task and its modeled fields, notes, tags, and subtasks. This is a demo exchange format, not a product archival-format commitment. It does not contain real SQLite files, attachments, or independently modeled review-page data. Restore accepts this format, validates required fields, shows the task count, and requires explicit replacement confirmation. Cancellation or an invalid file preserves current data. Return to the main window to load restored tasks. Export current tasks before replacement if you need to retain them.

The detail and list-editor pages remain isolated review specimens. Browser storage restrictions prevent cross-page preference and demo-data transfer; same-page controls retain an in-memory fallback. These browser limitations do not define the native application's data architecture.

## Implementation handoff

Native data-directory selection, consistent SQLite snapshots, actual backup recovery, portable export, multi-device merge behavior, language localization, and global shortcuts require product implementation. The prototype makes no promise that copying a live SQLite file through an arbitrary file-sync service is safe.
