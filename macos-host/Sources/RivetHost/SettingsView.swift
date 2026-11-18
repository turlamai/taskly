import AppKit
import SwiftUI

/// The Settings window (⌘,) panes (PRODUCT-SPEC §8 + §2a): General
/// (language, theme, auto-check updates), 新任务 (default list, recorded
/// global quick-add accelerator) and 数据 (current database + reveal,
/// migrate, open another, create, export JSON, restore backup). Every
/// control applies immediately through the same AppModel setters the
/// database lifecycle uses.
struct SettingsPaneView: View {
    @Environment(AppModel.self) private var model
    @State private var feedback = ""

    var body: some View {
        Form {
            Section {
                Picker(model.t("menuLanguage"), selection: Binding(
                    get: { model.i18n.language },
                    set: { model.setLanguage($0) })) {
                    Text(model.t("menuLangZh")).tag("zh")
                    Text(model.t("menuLangEn")).tag("en")
                }
                .pickerStyle(.menu)

                Picker(model.t("menuTheme"), selection: Binding(
                    get: { model.themeValue },
                    set: { model.setTheme($0) })) {
                    Text(model.t("themeFollowSystem")).tag("system")
                    Text(model.t("themeLight")).tag("light")
                    Text(model.t("themeDark")).tag("dark")
                }
                .pickerStyle(.menu)

                Toggle(model.t("settingsAutoCheckUpdates"), isOn: Binding(
                    get: { model.autoCheckUpdates },
                    set: { model.setAutoCheckUpdates($0) }))
            } header: {
                Text(model.t("menuSettings"))
            }

            Section {
                Picker(model.t("defaultListLabel"), selection: Binding(
                    get: { model.defaultListId },
                    set: { model.setDefaultList($0) })) {
                    Text("—").tag(Int64(0))
                    ForEach(model.lists, id: \.id) { list in
                        Text(list.name).tag(list.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!model.isConnected)

                ShortcutRecorderRow()
            } header: {
                Text(model.t("settingsGroupNewTasks"))
            } footer: {
                Text(model.t("defaultListHelp"))
            }

            Section {
                LabeledContent {
                    Button(model.t("dbReveal")) {
                        model.revealDatabaseFolder()
                    }
                    .buttonStyle(.secondaryTaskly)
                    .disabled(!model.isConnected)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.t("dbCurrentLabel"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(model.theme.onSurface)
                        Text(model.databaseName.isEmpty
                             ? model.t("dbCurrentNone") : model.databaseName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.theme.secondaryText)
                        Text(model.databasePath.isEmpty
                             ? model.t("dbPathNone") : model.databasePath)
                            .font(.system(size: 11))
                            .foregroundStyle(model.theme.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityIdentifier("settings-db-current")

                LabeledContent(model.t("dbLocationLabel")) {
                    Button(model.t("dbMigrateBtn")) {
                        model.databaseSheet = DatabaseSheetContext(mode: .migrate)
                    }
                    .buttonStyle(.secondaryTaskly)
                    .disabled(!model.isConnected)
                }
                .accessibilityIdentifier("settings-db-migrate")

                LabeledContent(model.t("dbSwitchLabel")) {
                    Button(model.t("dbOpenBtn")) {
                        AppModel.pickDatabaseFile { path in
                            if let path { model.openDatabase(path: path) }
                        }
                    }
                    .buttonStyle(.secondaryTaskly)
                }
                .accessibilityIdentifier("settings-db-open")

                LabeledContent(model.t("dbNewLabel")) {
                    Button(model.t("dbCreateBtn")) {
                        model.databaseSheet = DatabaseSheetContext(mode: .create)
                    }
                    .buttonStyle(.secondaryTaskly)
                }
                .accessibilityIdentifier("settings-db-create")

                LabeledContent(model.t("dbExportLabel")) {
                    Button(model.t("dbExportBtn")) { exportBackup() }
                        .buttonStyle(.secondaryTaskly)
                        .disabled(!model.isConnected)
                }
                .accessibilityIdentifier("settings-db-export")

                LabeledContent(model.t("dbRestoreLabel")) {
                    Button(model.t("dbRestoreBtn")) { pickBackup() }
                        .buttonStyle(.secondaryTaskly)
                        .disabled(!model.isConnected)
                }
                .accessibilityIdentifier("settings-db-restore")
            } header: {
                Text(model.t("settingsGroupData"))
            } footer: {
                Text(model.t("dbDataNote"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 720)
        .safeAreaInset(edge: .bottom) {
            if !feedback.isEmpty {
                Text(feedback)
                    .font(.system(size: 12))
                    .foregroundStyle(model.theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("settings-data-feedback")
            }
        }
        .onChange(of: model.databaseName) { _, _ in report("") }
        .onChange(of: model.databasePath) { _, _ in report("") }
        // Live language switch works without extra wiring: every label comes
        // from model.t(), whose read of languageChangedToken keeps the pane
        // observed on it.
    }

    private func report(_ message: String) { feedback = message }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "taskly-backup-\(Date().timeIntervalSince1970).json"
        panel.allowedContentTypes = [.json]
        panel.title = model.t("dbSaveBackup")
        // Non-modal for AX readability (same reason as AppModel.pick*).
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            _Concurrency.Task { @MainActor in
                do {
                    let count = try await model.exportBackup(to: url.path)
                    feedback = model.t("dbExported", Int(count))
                } catch {
                    model.dataFeedbackMessage = model.t(
                        "dbRestoreInvalid", AppModel.cleanError(error))
                }
            }
        }
    }

    /// §2a two-step restore: pick → core preview (counts) → the same
    /// sheet mechanism migrate uses (its confirm buttons are driver- and
    /// AX-reachable).
    private func pickBackup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.title = model.t("dbChooseBackup")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            _Concurrency.Task { @MainActor in
                do {
                    let preview = try await model.previewBackup(at: url.path)
                    model.databaseSheet = DatabaseSheetContext(
                        mode: .restore(path: url.path,
                                       taskCount: Int(preview.task_count),
                                       listCount: Int(preview.list_count),
                                       dbPathAtPreview: model.databasePath))
                } catch {
                    model.dataFeedbackMessage = model.t(
                        "dbRestoreInvalid", AppModel.cleanError(error))
                }
            }
        }
    }
}

/// §2a global quick-add recorder: captures one ⌘/⌃/⌥-modified keydown and
/// stores a normalized "ctrl+alt+space"-shaped string. Display-only — the
/// combination is never registered with the operating system (§2a scope).
struct ShortcutRecorderRow: View {
    @Environment(AppModel.self) private var model
    @State private var recording = false
    @State private var hint = ""
    /// The live key monitor while recording; nil otherwise.
    @State private var monitor: Any?

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 5) {
                Button(recording
                       ? model.t("shortcutRecording")
                       : (displayCombo.isEmpty ? model.t("shortcutNone") : displayCombo)) {
                    if recording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .buttonStyle(.secondaryTaskly)
                .accessibilityIdentifier("settings-quick-add-recorder")

                HStack(spacing: 10) {
                    Button(model.t("shortcutReset")) {
                        model.setGlobalQuickAdd("ctrl+alt+space")
                        hint = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(model.theme.secondaryText)
                    .underline()
                    Button(model.t("shortcutClear")) {
                        model.setGlobalQuickAdd("")
                        hint = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(model.theme.secondaryText)
                    .underline()
                }
                if !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(model.theme.tertiaryText)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("globalQuickAddLabel"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.theme.onSurface)
                Text(model.t("globalQuickAddHelp"))
                    .font(.system(size: 11))
                    .foregroundStyle(model.theme.tertiaryText)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var displayCombo: String {
        Self.format(model.globalQuickAdd)
    }

    /// Normalized config form → macOS glyphs (⌃⌥Space), empty → "".
    static func format(_ combo: String) -> String {
        guard !combo.isEmpty else { return "" }
        var out = ""
        for part in combo.split(separator: "+") {
            switch part.lowercased() {
            case "ctrl": out += "⌃"
            case "alt", "option": out += "⌥"
            case "shift": out += "⇧"
            case "cmd", "meta": out += "⌘"
            default: out += part.uppercased()
            }
        }
        return out
    }

    private func startRecording() {
        guard !recording else { return }
        recording = true
        hint = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape (keyCode 53) cancels without changes.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
            let hasModifier = flags.contains(.command) || flags.contains(.control)
                || flags.contains(.option)
            guard hasModifier else {
                hint = model.t("shortcutNeedModifier")
                return nil
            }
            var parts: [String] = []
            if flags.contains(.control) { parts.append("ctrl") }
            if flags.contains(.option) { parts.append("alt") }
            if flags.contains(.shift) { parts.append("shift") }
            if flags.contains(.command) { parts.append("cmd") }
            let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
            guard !key.isEmpty, key.count == 1 else { return nil }
            model.setGlobalQuickAdd((parts + [key]).joined(separator: "+"))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        recording = false
        hint = ""
    }
}
