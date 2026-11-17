import AppKit
import SwiftUI

// Database lifecycle surfaces (PRODUCT-SPEC §2a, prototype
// database-flow.js/main-window gate): the welcome + recovery gate and the
// create / migrate dialogs. Native hosts use real pickers where the
// prototype typed paths; dialog copy comes from i18n (db* keys).

/// Maps a core lifecycle error to the actionable i18n copy. Core messages
/// are machine-English (DATA-FORMAT §7 wording), so the known collisions
/// map to their dedicated keys; everything else carries the raw detail.
@MainActor
func databaseActionError(_ error: Error, _ model: AppModel,
                         fallback: String) -> String {
    let detail = AppModel.cleanError(error).lowercased()
    if detail.contains("already exists") { return model.t("dbErrExists") }
    if detail.contains("target already exists") { return model.t("dbErrTargetOccupied") }
    if detail.contains("equals the current location") { return model.t("dbErrTargetSame") }
    if detail.contains("not a taskly database") { return model.t("dbErrNotTaskly") }
    if detail.contains("file not found") { return model.t("dbErrOpenFailed", model.t("dbMissingPathFallback")) }
    return model.t(fallback, AppModel.cleanError(error))
}

extension AppModel {
    /// §2a open/relocate: file dialog over `*.db *.sqlite *.sqlite3`.
    /// Non-modal (`begin`): a `runModal` session locks the main thread and
    /// makes the panel's AX subtree unreadable from outside — the e2e
    /// driver (and accessibility tooling generally) can then neither find
    /// nor press its buttons.
    @MainActor
    static func pickDatabaseFile(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .init(filenameExtension: "db") ?? .data,
            .init(filenameExtension: "sqlite") ?? .data,
            .init(filenameExtension: "sqlite3") ?? .data,
        ]
        panel.begin { response in
            completion(response == .OK ? panel.url?.path : nil)
        }
    }

    /// §2a create/migrate: folder dialog (the prototype's typed folder
    /// entry is replaced by the platform picker). Non-modal — see above.
    @MainActor
    static func pickFolder(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            completion(response == .OK ? panel.url?.path : nil)
        }
    }
}

/// The §2a launch surface: welcome gate (no database recorded) or recovery
/// gate (recorded database failed to open). Rendered instead of the task UI.
struct DatabaseGateView: View {
    @Environment(AppModel.self) private var model

    private var isRecovery: Bool {
        if case .recovery = model.launchState { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            VStack(spacing: 16) {
                Text("Taskly")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.theme.accent)
                    .accessibilityIdentifier("database-wordmark")
                Text(isRecovery ? model.t("dbReconnectTitle") : model.t("dbGateTitle"))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(model.theme.onSurface)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("database-gate-title")
                Text(model.t("dbGateBody"))
                    .font(.system(size: 16))
                    .foregroundStyle(model.theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if isRecovery {
                    recoveryBlock
                } else {
                    choices
                }
            }
            .frame(maxWidth: 560)

            Text(model.t("dbGatePrinciple"))
                .font(.system(size: 14))
                .foregroundStyle(model.theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
        .background(model.theme.background)
    }

    private var choices: some View {
        HStack(spacing: 8) {
            Button(model.t("dbGateCreate")) {
                model.databaseSheet = DatabaseSheetContext(mode: .create)
            }
            .buttonStyle(.primaryTaskly)
            .accessibilityIdentifier("database-gate-create")

            Button(model.t("dbGateOpen")) {
                AppModel.pickDatabaseFile { path in
                    if let path { model.openDatabase(path: path) }
                }
            }
            .buttonStyle(.secondaryTaskly)
            .accessibilityIdentifier("database-gate-open")
        }
    }

    private var recoveryBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(model.theme.divider)
            Text(model.t("dbRecoveryTitle"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(model.theme.onSurface)
            if case .recovery(let path) = model.launchState {
                Text(path.isEmpty ? model.t("dbMissingPathFallback") : path)
                    .font(.system(size: 14))
                    .foregroundStyle(model.theme.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("database-recovery-path")
            }
            Text(model.t("dbRecoveryBody"))
                .font(.system(size: 14))
                .foregroundStyle(model.theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(model.t("dbRelocate")) {
                    AppModel.pickDatabaseFile { path in
                        if let path { model.openDatabase(path: path) }
                    }
                }
                .buttonStyle(.secondaryTaskly)
                .accessibilityIdentifier("database-recovery-relocate")
                Button(model.t("dbRetry")) {
                    model.retryRecordedDatabase()
                }
                .buttonStyle(.secondaryTaskly)
                .accessibilityIdentifier("database-recovery-retry")
            }
        }
        .frame(maxWidth: 560)
    }
}

/// Create / migrate dialog (one sheet per mode, §2a).
struct DatabaseSheetView: View {
    @Environment(AppModel.self) private var model
    let context: DatabaseSheetContext

    @State private var folder = ""
    @State private var name = ""
    @State private var confirming = false
    @State private var errorText = ""
    @State private var working = false

    private var isCreate: Bool { context.mode == .create }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isCreate ? model.t("dbCreateTitle") : model.t("dbMigrateTitle"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(model.theme.onSurface)
            Text(isCreate ? model.t("dbCreateDesc") : model.t("dbMigrateDesc"))
                .font(.system(size: 13))
                .foregroundStyle(model.theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !confirming {
                if isCreate {
                    fieldLabel(model.t("dbNameLabel"))
                    TextField(model.t("dbNameDefault"), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                        .accessibilityIdentifier("database-name-field")
                }
                fieldLabel(model.t("dbFolderLabel"))
                HStack(spacing: 8) {
                    Button(model.t("dbFolderChoose")) {
                        AppModel.pickFolder { picked in
                            if let picked {
                                folder = picked
                                errorText = ""
                            }
                        }
                    }
                    .buttonStyle(.secondaryTaskly)
                    .accessibilityIdentifier("database-folder-choose")
                    Text(folder.isEmpty ? "—" : folder)
                        .font(.system(size: 12))
                        .foregroundStyle(model.theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            } else {
                // §2a step 2: the explicit from → to confirmation.
                Text(model.t("dbMigrateConfirmText", model.databasePath,
                             migrationTarget))
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("database-migrate-confirm-text")
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundStyle(model.theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("database-error")
            }

            HStack {
                Spacer(minLength: 8)
                Button(model.t("dialogCancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.secondaryTaskly)
                Button(applyTitle) { apply() }
                    .buttonStyle(.primaryTaskly)
                    .disabled(working)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(isCreate
                        ? "database-create-apply" : "database-migrate-apply")
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(model.theme.surface)
        .onAppear {
            if isCreate { name = model.t("dbNameDefault") }
        }
    }

    private var migrationTarget: String {
        URL(fileURLWithPath: folder).appendingPathComponent("taskly.sqlite").path
    }

    private var applyTitle: String {
        isCreate
            ? model.t("dbApplyCreate")
            : (confirming ? model.t("dbConfirmMigrate") : model.t("dbApplyMigrate"))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(model.theme.secondaryText)
    }

    private func dismiss() {
        model.databaseSheet = nil
    }

    private func apply() {
        if isCreate {
            let cleanName = name.trimmingCharacters(in: .whitespaces)
            if cleanName.isEmpty || cleanName.range(of: #"[\\/:*?"<>|]"#) != nil {
                errorText = model.t("dbErrBadName")
                return
            }
            guard !folder.isEmpty else {
                errorText = model.t("dbErrNoPath")
                return
            }
            working = true
            _Concurrency.Task {
                do {
                    try await model.createDatabase(folder: folder, name: cleanName)
                    dismiss()
                } catch {
                    errorText = databaseActionError(error, model,
                                                    fallback: "dbErrCreateFailed")
                    working = false
                }
            }
        } else if !confirming {
            guard !folder.isEmpty else {
                errorText = model.t("dbErrNoPath")
                return
            }
            confirming = true
            errorText = ""
        } else {
            working = true
            _Concurrency.Task {
                do {
                    try await model.migrateDatabase(folder: folder)
                    dismiss()
                } catch {
                    errorText = databaseActionError(error, model,
                                                    fallback: "dbErrMigrateFailed")
                    confirming = false
                    working = false
                }
            }
        }
    }
}

/// Shared quiet/primary button language for the lifecycle surfaces.
struct PrimaryTasklyButtonStyle: ButtonStyle {
    @Environment(AppModel.self) private var model

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(model.theme.accentInk)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(model.theme.accent))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryTasklyButtonStyle: ButtonStyle {
    @Environment(AppModel.self) private var model

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(model.theme.onSurface)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed
                          ? model.theme.selection : model.theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(model.theme.inputBorder, lineWidth: 1))
    }
}

extension ButtonStyle where Self == PrimaryTasklyButtonStyle {
    static var primaryTaskly: PrimaryTasklyButtonStyle { PrimaryTasklyButtonStyle() }
}

extension ButtonStyle where Self == SecondaryTasklyButtonStyle {
    static var secondaryTaskly: SecondaryTasklyButtonStyle { SecondaryTasklyButtonStyle() }
}
