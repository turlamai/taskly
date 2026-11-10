import AppKit
import SwiftUI

/// Taskly macOS host: one SwiftUI window over the embedded Racket backend.
@main
struct TasklyApp: App {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Taskly") {
            MainWindowView()
                .environment(model)
                .frame(
                    minWidth: 760, idealWidth: 1024,
                    minHeight: 520, idealHeight: 768)
                .task { model.start() }
        }
        .defaultSize(width: 1280, height: 880)
        .commands {
            TasklyCommands(model: model)
            // Strip system-injected noise that is outside PRODUCT-SPEC §8:
            // toolbar/sidebar/tab-bar groups (which otherwise spawn a second
            // View menu).
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .appInfo) {
                Button(model.t("menuAbout")) {
                    model.aboutVisible = true
                }
            }
            // Family menu convention: Check for Updates… lives in the App
            // menu directly below About.
            CommandGroup(after: .appInfo) {
                Button(model.t("menuCheckUpdates")) { model.checkForUpdates() }
            }
            // Own the Settings… item (like About/Quit above). The Settings
            // *scene* would auto-seed an AppKit-English item whose title it
            // re-seeds on every resync — retitle and prune both lose that
            // race — so the scene is not used: the pane lives in a plain
            // named window and this is the only Settings item there is.
            CommandGroup(replacing: .appSettings) {
                Button(model.t("menuSettings") + "…") {
                    openWindow(id: "app-settings")
                }
                .keyboardShortcut(",")
            }
            // Localized Quit (the system item is AppKit-English regardless of
            // the app language); terminate stays the normal path.
            CommandGroup(replacing: .appTermination) {
                Button(model.t("menuExit")) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }

        // App preferences live in the standard Settings window (⌘,) — the
        // macOS convention for persistent preferences (HIG/Sparkle); a
        // menu-bar 设置 menu with a bare toggle is not an idiom macOS users
        // expect. Same three preferences as the Windows 设置 menu (issue #118):
        // language, theme, auto-check-updates, same persistence keys. A plain
        // named Window instead of the Settings scene so SwiftUI does not seed
        // its unlocalizable English menu item.
        Window(model.t("menuSettings"), id: "app-settings") {
            SettingsPaneView()
                .environment(model)
        }
        .windowResizability(.contentSize)
    }
}

/// Native menu bar (localized, live language switch).
struct TasklyCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(model.t("menuNewDatabase")) { newDatabase() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button(model.t("menuOpenDatabase")) { openDatabase() }
                .keyboardShortcut("o", modifiers: [.command])
        }
        // Close lives in the save/close group: a replaced group must not be
        // empty — SwiftUI re-seeds empty groups' boundary separators on every
        // menu resync. This also displaces the system Close/Close All, whose
        // plain Cmd+W collided with Close Database.
        CommandGroup(replacing: .saveItem) {
            Button(model.t("menuCloseDatabase")) { confirmClose() }
                .disabled(!model.isConnected)
        }
        // View menu mirrors PRODUCT-SPEC §8: smart views, quick add /
        // search focus, show-completed toggle.
        CommandMenu(model.t("menuView")) {
            Button(model.t("navToday")) { model.select(.today) }
                .keyboardShortcut("1", modifiers: [.command])
            Button(model.t("navPlanned")) { model.select(.planned) }
                .keyboardShortcut("2", modifiers: [.command])
            Button(model.t("navAll")) { model.select(.all) }
                .keyboardShortcut("3", modifiers: [.command])
            Button(model.t("navCompleted")) { model.select(.completed) }
                .keyboardShortcut("4", modifiers: [.command])
            Divider()
            Button(newTaskMenuTitle) { model.quickAddFocusToken += 1 }
                .keyboardShortcut("n", modifiers: [.command])
            Button(model.t("searchHint")) { model.searchFocusToken += 1 }
                .keyboardShortcut("f", modifiers: [.command])
            Divider()
            Toggle(model.t("showCompletedToggle"), isOn: Binding(
                get: { model.showCompleted },
                set: {
                    model.showCompleted = $0
                    model.reload()
                }))
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        // (语言/主题/auto-check preferences live in the app-settings window —
        // see the Window scene in TasklyApp.)
    }

    /// Windows trims the "+ " prompt off the quick-add hint for the
    /// View-menu item; keep the same label ("添加任务" / "Add Task").
    private var newTaskMenuTitle: String {
        String(model.t("taskListInputHint").drop(while: { $0 == "+" || $0 == " " }))
    }

    private func newDatabase() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tasks"
        panel.allowedContentTypes = [
            .init(filenameExtension: "db") ?? .data
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.openDatabase(path: url.path)
    }

    private func openDatabase() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .init(filenameExtension: "db") ?? .data
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.openDatabase(path: url.path)
    }

    private func confirmClose() {
        let alert = NSAlert()
        alert.messageText = model.t("dialogConfirmCloseDb")
        alert.informativeText = model.t("dialogConfirmCloseDbContent")
        alert.addButton(withTitle: model.t("dialogConfirm"))
        alert.addButton(withTitle: model.t("dialogCancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.closeDatabase()
    }
}
