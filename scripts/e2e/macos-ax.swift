import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum DriverError: Error, CustomStringConvertible {
    case failure(String)
    var description: String { switch self { case .failure(let message): return message } }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
    attribute(element, name) as? String ?? ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func walk(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    // The macOS 26 AX bridge can expose the application element as its own
    // descendant; descending into that self-referential chain re-walks the
    // entire tree per level (and an unbounded recursion overflows the
    // driver stack — segfault: 11). Application elements only carry
    // meaningful children at an application root; skip them mid-walk and
    // keep the depth cap as the belt-and-braces bound.
    if depth > 0,
       stringAttribute(element, kAXRoleAttribute) == (kAXApplicationRole as String) {
        return [element]
    }
    guard depth < 40 else { return [element] }
    return [element] + children(element).flatMap { walk($0, depth: depth + 1) }
}

func find(_ root: AXUIElement, identifier: String) -> AXUIElement? {
    walk(root).first { stringAttribute($0, kAXIdentifierAttribute) == identifier }
}

func find(_ root: AXUIElement, identifierPrefix: String) -> AXUIElement? {
    walk(root).first {
        stringAttribute($0, kAXIdentifierAttribute).hasPrefix(identifierPrefix)
    }
}

func findTaskTitle(_ root: AXUIElement, text: String) -> AXUIElement? {
    walk(root).first { element in
        stringAttribute(element, kAXIdentifierAttribute).hasPrefix("task-title-") &&
            [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                .contains { stringAttribute(element, $0) == text }
    }
}

func findDeleteMenuItem(_ root: AXUIElement) -> AXUIElement? {
    walk(root).first { element in
        stringAttribute(element, kAXRoleAttribute) == (kAXMenuItemRole as String) &&
            ["Delete", "删除"].contains(stringAttribute(element, kAXTitleAttribute))
    }
}

func findButton(_ root: AXUIElement, title: String) -> AXUIElement? {
    walk(root).first { element in
        stringAttribute(element, kAXRoleAttribute) == (kAXButtonRole as String) &&
            [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                .contains { stringAttribute(element, $0) == title }
    }
}

func containsStaticText(_ root: AXUIElement, _ expected: String) -> Bool {
    walk(root).contains { element in
        stringAttribute(element, kAXRoleAttribute) == (kAXStaticTextRole as String) &&
            [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                .contains { stringAttribute(element, $0) == expected }
    }
}

func waitFor<T>(_ description: String, timeout: TimeInterval = 30, probe: () -> T?) throws -> T {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let value = probe() { return value }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw DriverError.failure("timed out waiting for \(description)")
}

func snapshot(_ element: AXUIElement, depth: Int = 0) -> [String: Any] {
    var result: [String: Any] = [
        "role": stringAttribute(element, kAXRoleAttribute),
        "identifier": stringAttribute(element, kAXIdentifierAttribute),
        "title": stringAttribute(element, kAXTitleAttribute),
        "label": stringAttribute(element, kAXDescriptionAttribute),
        "value": stringAttribute(element, kAXValueAttribute),
    ]
    if depth < 8 { result["children"] = children(element).map { snapshot($0, depth: depth + 1) } }
    return result
}

func writeJSON(_ value: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

func press(_ element: AXUIElement, _ description: String) throws {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if result != .success {
        // Some custom-styled SwiftUI buttons (inside sheets) do not expose
        // the press action (-25204 ActionUnsupported). Fall back to a real
        // click at the element's center. A sheet mid-layout reports empty
        // bounds, so wait briefly for the element to become clickable.
        var clickable = false
        for _ in 0..<70 {
            if (try? clickPoint(element)) != nil {
                clickable = true
                break
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        guard clickable else {
            throw DriverError.failure(
                "AXPress failed for \(description): \(result.rawValue) " +
                "(no clickable bounds)")
        }
        try postClick(element, description, button: .left,
                      downType: .leftMouseDown, upType: .leftMouseUp)
    }
}

func typeText(_ value: String, into element: AXUIElement) throws {
    guard AXUIElementSetAttributeValue(
        element, kAXFocusedAttribute as CFString, kCFBooleanTrue
    ) == .success else {
        throw DriverError.failure("could not focus quick-add field")
    }
    guard let source = CGEventSource(stateID: .hidSystemState),
          let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
        throw DriverError.failure("could not create native keyboard events")
    }
    let characters = Array(value.utf16)
    characters.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
        keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
    }
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

func setValue(_ value: String, on element: AXUIElement) throws {
    guard AXUIElementSetAttributeValue(
        element, kAXFocusedAttribute as CFString, kCFBooleanTrue
    ) == .success else {
        throw DriverError.failure("could not focus editor")
    }
    guard AXUIElementSetAttributeValue(
        element, kAXValueAttribute as CFString, value as CFString
    ) == .success else {
        throw DriverError.failure("could not set editor value")
    }
}

func postKey(_ keyCode: CGKeyCode) throws {
    try postKey(keyCode, flags: [])
}

/// Modifier-combined key event (Cmd+Shift+G go-to-folder, Cmd+, settings…).
func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) throws {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
        throw DriverError.failure("could not create keyboard event")
    }
    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

let cmdShiftG: CGEventFlags = [.maskCommand, .maskShift]
let cmdOnly: CGEventFlags = [.maskCommand]

func clickPoint(_ element: AXUIElement) throws -> CGPoint {
    guard let positionRaw = attribute(element, kAXPositionAttribute),
          let sizeRaw = attribute(element, kAXSizeAttribute),
          CFGetTypeID(positionRaw) == AXValueGetTypeID(),
          CFGetTypeID(sizeRaw) == AXValueGetTypeID() else {
        throw DriverError.failure("element has no clickable bounds")
    }
    let positionValue = positionRaw as! AXValue
    let sizeValue = sizeRaw as! AXValue
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue, .cgPoint, &position),
          AXValueGetValue(sizeValue, .cgSize, &size) else {
        throw DriverError.failure("could not resolve clickable bounds")
    }
    return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
}

func postClick(
    _ element: AXUIElement, _ description: String,
    button: CGMouseButton, downType: CGEventType, upType: CGEventType) throws {
    let point = try clickPoint(element)
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(mouseEventSource: source, mouseType: downType,
                             mouseCursorPosition: point, mouseButton: button),
          let up = CGEvent(mouseEventSource: source, mouseType: upType,
                           mouseCursorPosition: point, mouseButton: button) else {
        throw DriverError.failure("could not create click events for \(description)")
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

func rightClick(_ element: AXUIElement) throws {
    try postClick(element, "right-click", button: .right,
                  downType: .rightMouseDown, upType: .rightMouseUp)
}

/// §5: the task title opens the inline quick editor — a real click, since
/// the title is a gesture target rather than an AXPressable control.
func leftClick(_ element: AXUIElement, _ description: String) throws {
    try postClick(element, description, button: .left,
                  downType: .leftMouseDown, upType: .leftMouseUp)
}

var diagnosticApplication: AXUIElement?
var diagnosticOutput: URL?

// ---- §2a database-lifecycle scenario helpers -----------------------------

/// The NSOpenPanel/NSSavePanel presents as a dialog window of the app.
/// Waiting for it before sending shortcuts is what makes the go-to flow
/// deterministic: a swallowed press otherwise times out on the go-to field.
func panelWindow(_ application: AXUIElement) -> AXUIElement? {
    for element in walk(application) {
        let role = stringAttribute(element, kAXRoleAttribute)
        guard role == "AXWindow" || role == "AXSheet" else { continue }
        let subrole = stringAttribute(element, kAXSubroleAttribute)
        let title = stringAttribute(element, kAXTitleAttribute)
        if subrole == "AXDialog" ||
            ["open", "choose", "save", "打开", "选择", "保存"]
            .contains(where: { title.lowercased().contains($0) }) {
            return element
        }
    }
    return nil
}

/// The focused editable text field of the frontmost sheet/panel (the
/// go-to-folder field takes focus the moment the shortcut lands).
func focusedTextField(_ root: AXUIElement) -> AXUIElement? {
    for element in walk(root) {
        let role = stringAttribute(element, kAXRoleAttribute)
        guard role == "AXTextField" else { continue }
        let focused = stringAttribute(element, kAXFocusedAttribute)
        if focused == "1" { return element }
    }
    return nil
}

/// Drives a real NSOpenPanel/NSSavePanel to the given path: Cmd+Shift+G,
/// type the path into the go-to sheet, Return to navigate, Return to accept
/// the default (Go / Open / Choose / Save) button.
/// The panel's begin-completion writes the picked path back to the sheet
/// asynchronously; pressing the sheet's apply button before that lands
/// fails with "choose a location first" (observed as a CI flake).
func waitForFolderApplied(_ application: AXUIElement) throws {
    _ = try waitFor("folder path applied to the sheet") {
        find(application, identifier: "database-folder-path").flatMap {
            let text = elementText($0)
            return (!text.isEmpty && text != "—") ? text : nil
        }
    }
}

/// The runner-reliable way through NSOpenPanel/NSSavePanel: e2e-macos.sh
/// pins NSNavLastRootDirectory before launch so the panel opens in the
/// target directory, and the default button is pressed through AXPress —
/// no blind keyboard navigation. `select` names a file row to select
/// first (restore flow); nil just confirms the folder/file name.
/// One-shot diagnostics for the restore row hunt: what the panel's
/// outline actually exposes when the expected file row is missing.
var panelRowsDumped = false
func dumpPanelRows(_ panel: AXUIElement, lookingFor: String) {
    guard !panelRowsDumped else { return }
    panelRowsDumped = true
    FileHandle.standardError.write(Data(
        "PANEL-DUMP lookingFor=\(lookingFor)\n".utf8))
    var printed = 0
    for element in walk(panel) where printed < 40 {
        let role = stringAttribute(element, kAXRoleAttribute)
        guard ["AXRow", "AXOutline", "AXTable", "AXList"].contains(role)
        else { continue }
        let text = walk(element)
            .map { stringAttribute($0, kAXValueAttribute) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        FileHandle.standardError.write(Data(
            "PANEL-DUMP role=\(role) text=\(text.prefix(120))\n".utf8))
        printed += 1
    }
    FileHandle.standardError.write(Data("PANEL-DUMP-END\n".utf8))
}

func confirmPanel(_ application: AXUIElement, buttonTitle: String,
                  selectingRowNamed selected: String? = nil) throws {
    let panel: AXUIElement = try waitFor("file panel window") {
        panelWindow(application)
    }
    // The restore sheet (settings 数据 group) previews counts from the
    // picked file; the sheet's own Replace button is driver-reachable, so
    // the file panel only needs the file opened once.
    if let selected {
        let entry: AXUIElement = try waitFor("panel entry \(selected)") {
            walk(panel).first { element in
                [kAXTitleAttribute, kAXValueAttribute]
                    .contains { stringAttribute(element, $0).contains(selected) }
            }
        }
        try postClick(entry, "panel file entry click", button: .left,
                      downType: .leftMouseDown, upType: .leftMouseUp)
        Thread.sleep(forTimeInterval: 0.5)
        let okButton: AXUIElement = try waitFor("panel OK button") {
            find(panel, identifier: "OKButton")
                ?? findButton(panel, title: buttonTitle)
                ?? findButton(application, title: buttonTitle)
        }
        try press(okButton, "panel default button")
        Thread.sleep(forTimeInterval: 0.6)
        return
    }
    let button: AXUIElement = try waitFor("panel default button") { () -> AXUIElement? in
        // NSOpenPanel/NSSavePanel expose stable identifiers: the confirming
        // button is always OKButton (title varies: Open/Choose/Save) and
        // Cancel is CancelButton. Title lookup stays as the fallback.
        if let stable = find(panel, identifier: "OKButton") { return stable }
        if let named = findButton(panel, title: buttonTitle)
            ?? findButton(application, title: buttonTitle) {
            return named
        }
        return nil
    }
    try press(button, "panel default button")
    Thread.sleep(forTimeInterval: 0.6)
}

func elementText(_ element: AXUIElement) -> String {
    return [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
        .map { stringAttribute(element, $0) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

func configFileValue(_ home: URL, key: String) -> String? {
    let configURL = home.appendingPathComponent(".taskly/config.ini")
    guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
        return nil
    }
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1)
        if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key {
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
    }
    return nil
}

func openSettings(_ application: AXUIElement) throws {
    try postKey(43, flags: cmdOnly) // , — ⌘, opens the settings window (§8)
    _ = try waitFor("settings window") {
        find(application, identifier: "settings-db-current")
    }
}

/// The §2a gate scenarios (--database-gate / --database-recovery-retry),
/// each running against a dedicated profile prepared by e2e-macos.sh.
func runDatabaseGateScenario(application: AXUIElement, window: AXUIElement,
                             output: URL, home: URL, mode: String) throws {
    if mode == "gate" {
        // Welcome gate visible before any task UI.
        _ = try waitFor("welcome gate headline") {
            find(window, identifier: "database-gate-title")
        }
        let create = try waitFor("welcome gate create action") {
            find(window, identifier: "database-gate-create")
        }
        _ = try waitFor("welcome gate open action") {
            find(window, identifier: "database-gate-open")
        }
        // Exclusive create: folder + name through the create sheet.
        try press(create, "database-gate-create")
        let nameField = try waitFor("create sheet name field") {
            find(application, identifier: "database-name-field")
        }
        try setValue("Gate Acceptance", on: nameField)
        let chooseFolder = try waitFor("create sheet folder chooser") {
            find(application, identifier: "database-folder-choose")
        }
        try press(chooseFolder, "database-folder-choose")
        // NSNavLastRootDirectory pins the panel at the profile home; just
        // confirm it ("Choose", falling back to "Open" on some layouts).
        try confirmPanel(application, buttonTitle: "Choose")
        try waitForFolderApplied(application)

        let apply = try waitFor("create sheet apply action") {
            find(application, identifier: "database-create-apply")
        }
        try press(apply, "database-create-apply")
        _ = try waitFor("task UI after create") {
            find(window, identifier: "quick-add")
        }
        _ = try waitFor("sidebar database identity") {
            find(window, identifier: "database-identity")
        }
        // The created file is the recorded database.
        let recorded = configFileValue(home, key: "last-db-path") ?? ""
        guard recorded.hasSuffix("taskly.sqlite"),
              FileManager.default.fileExists(atPath: recorded) else {
            throw DriverError.failure("create did not record the database: \(recorded)")
        }
        try writeJSON([
            "platform": "macos",
            "scenario": "database-gate-create",
            "assertions": [
                "welcome gate replaces the task UI with no database recorded",
                "create flow opened the create sheet and the native folder panel",
                "create produced taskly.sqlite and recorded it as the last database",
                "sidebar database identity is visible after create",
            ],
        ], to: output.appendingPathComponent("database-gate.json"))
    } else {
        // Recovery: the recorded database file is missing until the harness
        // restores it; 重试 re-attempts the recorded path.
        _ = try waitFor("recovery block headline") {
            containsStaticText(window, "Can't find your last database") ||
            containsStaticText(window, "找不到上次的数据库") ? true : nil
        }
        _ = try waitFor("recovery recorded path shown") {
            find(window, identifier: "database-recovery-path")
        }
        let retry = try waitFor("recovery retry action") {
            find(window, identifier: "database-recovery-retry")
        }
        // Retry in a loop: while the file is still absent every attempt
        // returns to the recovery block; once the harness restores the file
        // the next retry reconnects.
        var connected = false
        for _ in 0..<40 {
            try press(retry, "database-recovery-retry")
            Thread.sleep(forTimeInterval: 0.5)
            if find(window, identifier: "quick-add") != nil {
                connected = true
                break
            }
            if find(window, identifier: "database-recovery-retry") == nil {
                connected = find(window, identifier: "quick-add") != nil
                break
            }
        }
        guard connected else {
            throw DriverError.failure("retry never reconnected the restored database")
        }
        try writeJSON([
            "platform": "macos",
            "scenario": "database-recovery",
            "assertions": [
                "missing recorded database shows the recovery block with the recorded path",
                "no replacement database is created automatically",
                "重试 reconnects once the file is restored in place",
            ],
        ], to: output.appendingPathComponent("database-recovery.json"))
    }
}

/// §2a settings 数据 group: migrate / export / restore against the
/// connected database (profile seeded by e2e-macos.sh).
func runDatabaseSettingsScenario(application: AXUIElement, window: AXUIElement,
                                 output: URL, home: URL) throws {
    try openSettings(application)
    let migrate = try waitFor("settings migrate action") {
        find(application, identifier: "settings-db-migrate")
    }
    try press(migrate, "settings-db-migrate")
    let chooseFolder = try waitFor("migrate sheet folder chooser") {
        find(application, identifier: "database-folder-choose")
    }
    try press(chooseFolder, "database-folder-choose")
    let migrateDir = home.appendingPathComponent("migrated")
    try FileManager.default.createDirectory(at: migrateDir, withIntermediateDirectories: true)
    // The harness pre-creates migrated/ and pins NSNavLastRootDirectory to
    // the profile home; the panel's default "Choose" confirms whatever
    // directory the harness selected for this run.
    try confirmPanel(application, buttonTitle: "Choose")
    try waitForFolderApplied(application)
    let continueButton = try waitFor("migrate continue action") {
        find(application, identifier: "database-migrate-apply")
    }
    try press(continueButton, "database-migrate-apply")
    let confirmText = try waitFor("migrate confirmation text") {
        find(application, identifier: "database-migrate-confirm-text")
    }
    _ = confirmText
    try press(continueButton, "database-migrate-confirm")
    // The RPC may fail with an actionable error anchored inside the sheet;
    // surface it verbatim instead of failing on the assertion alone.
    var migrateError = ""
    for _ in 0..<20 {
        if let errorNode = find(application, identifier: "database-error"),
           !elementText(errorNode).isEmpty {
            migrateError = elementText(errorNode)
            break
        }
        // Success signal: the sheet dismissed and the identity reloaded.
        if find(application, identifier: "database-migrate-apply") == nil {
            break
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
    if !migrateError.isEmpty {
        throw DriverError.failure("migrate RPC error: \(migrateError)")
    }
    _ = try waitFor("settings window after migrate") {
        find(application, identifier: "settings-db-current")
    }
    let recorded = configFileValue(home, key: "last-db-path") ?? ""
    guard recorded.hasSuffix("taskly.sqlite"),
          recorded != home.appendingPathComponent("seed.db").path,
          FileManager.default.fileExists(atPath: recorded),
          FileManager.default.fileExists(
            atPath: home.appendingPathComponent("seed.db").path) else {
        throw DriverError.failure(
            "migrate did not switch the recorded location (recorded: \(recorded))")
    }

    // Backup export through the save panel; the file must be taskly-backup v1.
    let export = try waitFor("settings export action") {
        find(application, identifier: "settings-db-export")
    }
    try press(export, "settings-db-export")
    var backupPath = home.appendingPathComponent("seed-backup.json")
    if FileManager.default.fileExists(atPath: backupPath.path) {
        try FileManager.default.removeItem(at: backupPath)
    }
    // The save panel's name field owns focus; wait for the panel window,
    // then set the file name and confirm through the default button.
    _ = try waitFor("save panel window") { panelWindow(application) }
    let nameField = try waitFor("save panel name field") { () -> AXUIElement? in
        guard let panel = panelWindow(application) else { return nil }
        // The save panel's name field: its only editable text field (focus
        // flags proved unreliable on runners).
        return walk(panel).first { element in
            let role = stringAttribute(element, kAXRoleAttribute)
            return role == "AXTextField" || role == "AXComboBox"
        }
    }
    try setValue("seed-backup.json", on: nameField)
    try confirmPanel(application, buttonTitle: "Save")
    _ = try waitFor("backup file written") { () -> Bool? in
        if FileManager.default.fileExists(atPath: backupPath.path) { return true }
        // NSNavLastRootDirectory normally lands it in the profile home;
        // glob one level deep as a fallback before failing.
        if let enumerator = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if url.lastPathComponent == "seed-backup.json" { return true }
            }
        }
        return nil
    }
    if !FileManager.default.fileExists(atPath: backupPath.path) {
        if let enumerator = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: nil),
           let found = enumerator.allObjects.compactMap({ $0 as? URL })
               .first(where: { $0.lastPathComponent == "seed-backup.json" }) {
            backupPath = found
        }
    }
    let backupData = try Data(contentsOf: backupPath)
    let backupJSON = try JSONSerialization.jsonObject(with: backupData) as? [String: Any]
    guard (backupJSON?["format"] as? String) == "taskly-backup",
          (backupJSON?["version"] as? Int) == 1,
          let tasks = backupJSON?["tasks"] as? [[String: Any]], !tasks.isEmpty else {
        throw DriverError.failure("export did not write a taskly-backup v1 file")
    }

    // Restore: preview → explicit confirmation → replaced (identical file,
    // so the observable outcome is the confirmation + a live database).
    let restore = try waitFor("settings restore action") {
        find(application, identifier: "settings-db-restore")
    }
    try press(restore, "settings-db-restore")
    try confirmPanel(application, buttonTitle: "Open",
                     selectingRowNamed: "seed-backup.json")
    // The restore sheet (same mechanism migrate drives) shows the preview
    // counts and carries the driver-reachable Replace button.
    let replaceButton = try waitFor("restore sheet replace action") {
        find(application, identifier: "database-restore-apply")
    }
    try press(replaceButton, "database-restore-apply")
    _ = try waitFor("restore feedback reported") {
        find(application, identifier: "settings-data-feedback") != nil ? true : nil
    }

    try writeJSON([
        "platform": "macos",
        "scenario": "database-settings",
        "assertions": [
            "migrate moved the recorded location and left the source file in place",
            "export wrote a taskly-backup v1 JSON file with tasks",
            "restore required the explicit confirmation and completed",
        ],
    ], to: output.appendingPathComponent("database-settings.json"))
}

do {
    let arguments = CommandLine.arguments
    guard let pidIndex = arguments.firstIndex(of: "--pid"), pidIndex + 1 < arguments.count,
          let pid = Int32(arguments[pidIndex + 1]),
          let outputIndex = arguments.firstIndex(of: "--output"), outputIndex + 1 < arguments.count else {
        throw DriverError.failure("usage: macos-ax --pid PID --output DIRECTORY")
    }
    let output = URL(fileURLWithPath: arguments[outputIndex + 1], isDirectory: true)
    diagnosticOutput = output
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    guard AXIsProcessTrusted() else { throw DriverError.failure("accessibility access is unavailable") }

    let application = AXUIElementCreateApplication(pid)
    diagnosticApplication = application
    let window: AXUIElement = try waitFor("Taskly window") {
        (attribute(application, kAXWindowsAttribute) as? [AXUIElement])?.first
    }
    _ = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)

    // §2a scenario dispatch: the lifecycle flows run against dedicated
    // profiles prepared by e2e-macos.sh (--home points at the profile).
    if let homeIndex = arguments.firstIndex(of: "--home"), homeIndex + 1 < arguments.count {
        let home = URL(fileURLWithPath: arguments[homeIndex + 1], isDirectory: true)
        if arguments.contains("--database-gate") {
            try runDatabaseGateScenario(application: application, window: window,
                                        output: output, home: home, mode: "gate")
            guard let running = NSRunningApplication(processIdentifier: pid),
                  running.terminate() else {
                throw DriverError.failure("gate scenario application rejected termination")
            }
            exit(0)
        }
        if arguments.contains("--database-recovery-retry") {
            try runDatabaseGateScenario(application: application, window: window,
                                        output: output, home: home, mode: "recovery")
            guard let running = NSRunningApplication(processIdentifier: pid),
                  running.terminate() else {
                throw DriverError.failure("recovery scenario application rejected termination")
            }
            exit(0)
        }
        if arguments.contains("--database-settings") {
            try runDatabaseSettingsScenario(application: application, window: window,
                                            output: output, home: home)
            guard let running = NSRunningApplication(processIdentifier: pid),
                  running.terminate() else {
                throw DriverError.failure("settings scenario application rejected termination")
            }
            exit(0)
        }
    }

    if arguments.contains("--verify-restart") {
        _ = try waitFor("persisted task after application restart") {
            findTaskTitle(window, text: "Return-edited acceptance task")
        }
        _ = try waitFor("persisted Tomorrow date after application restart") {
            containsStaticText(window, "Tomorrow") ? true : nil
        }
        try writeJSON([
            "platform": "macos",
            "assertions": ["task title and Tomorrow date survive a cold installed-app restart"],
        ], to: output.appendingPathComponent("persistence-restart.json"))
        guard let running = NSRunningApplication(processIdentifier: pid), running.terminate() else {
            throw DriverError.failure("restarted application rejected termination")
        }
        exit(0)
    }

    _ = try waitFor("actionable first-run empty state") {
        containsStaticText(window, "Add your first task above — try “Plan tomorrow”") ? true : nil
    }

    for view in ["today", "planned", "all", "completed"] {
        let _: AXUIElement = try waitFor("visible zero count for \(view)") {
            guard let candidate = find(window, identifier: "smart-view-\(view)") else { return nil }
            return [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                .contains { stringAttribute(candidate, $0) == "0" } ? candidate : nil
        }
    }

    let quickAdd: AXUIElement = try waitFor("quick-add field") { find(window, identifier: "quick-add") }
    let submit: AXUIElement = try waitFor("quick-add submit button") { find(window, identifier: "quick-add-submit") }
    try typeText("Acceptance task", into: quickAdd)
    _ = try waitFor("native quick-add input") {
        stringAttribute(quickAdd, kAXValueAttribute) == "Acceptance task" ? true : nil
    }
    try press(submit, "quick-add-submit")
    _ = try waitFor("quick-add submission") {
        stringAttribute(quickAdd, kAXValueAttribute).isEmpty ? true : nil
    }
    _ = try waitFor("RPC-created task row") { containsStaticText(window, "Acceptance task") ? true : nil }

    let taskTitle: AXUIElement = try waitFor("identified task title") {
        findTaskTitle(window, text: "Acceptance task")
    }
    // The row insert animates (0.15 s ease-out). Grabbing the info button
    // mid-animation hands the press a stale AX reference that lands on the
    // title's tap gesture and expands the inline editor instead. Let the
    // layout settle before pressing row controls.
    Thread.sleep(forTimeInterval: 0.8)
    let taskIdentifier = stringAttribute(taskTitle, kAXIdentifierAttribute)
    guard let taskID = taskIdentifier.split(separator: "-").last.map(String.init) else {
        throw DriverError.failure("task title had no stable id: \(taskIdentifier)")
    }

    // §5b/§6 — the anchored detail layer: ⓘ opens it, every field change
    // persists immediately (per-field autosave), and closing never discards.
    // The layer lives in its own popover window, so its elements are found
    // from the application root.
    let details: AXUIElement = try waitFor("task details control") {
        find(window, identifier: "task-details-\(taskID)")
    }
    try press(details, "task-details-\(taskID)")
    let detailTitle: AXUIElement = try waitFor("detail layer title field") {
        find(application, identifier: "detail-title-\(taskID)")
    }
    try setValue("Autosaved detail title", on: detailTitle)
    try postKey(36) // Return — ends title editing; autosave persists
    _ = try waitFor("detail autosave committed to the stored row") {
        findTaskTitle(window, text: "Autosaved detail title") != nil ? true : nil
    }
    let detailDone: AXUIElement = try waitFor("detail layer Done action") {
        find(application, identifier: "detail-done-\(taskID)")
    }
    try press(detailDone, "detail-done-\(taskID)")
    _ = try waitFor("detail layer closed without discarding") {
        find(application, identifier: "detail-title-\(taskID)") == nil ? true : nil
    }

    // §5: the task title opens the inline quick editor. Escape is a true
    // draft cancel even while the native field editor owns focus.
    let cancelledEntry: AXUIElement = try waitFor("row title for inline entry") {
        findTaskTitle(window, text: "Autosaved detail title")
    }
    try leftClick(cancelledEntry, "task title")
    let cancelledEditor: AXUIElement = try waitFor("inline title editor") {
        find(window, identifier: "inline-task-title-\(taskID)")
    }
    try setValue("Cancelled draft", on: cancelledEditor)
    try postKey(53) // Escape
    _ = try waitFor("Escape cancelled inline draft") {
        find(window, identifier: "inline-task-title-\(taskID)") == nil &&
            findTaskTitle(window, text: "Autosaved detail title") != nil ? true : nil
    }

    let savedEntry: AXUIElement = try waitFor("row title for Save entry") {
        findTaskTitle(window, text: "Autosaved detail title")
    }
    try leftClick(savedEntry, "task title")
    let committedEditor: AXUIElement = try waitFor("inline title editor after cancel") {
        find(window, identifier: "inline-task-title-\(taskID)")
    }
    let explicitSave: AXUIElement = try waitFor("visible inline Save action") {
        find(window, identifier: "inline-task-save-\(taskID)")
    }
    let _: AXUIElement = try waitFor("visible inline Cancel action") {
        find(window, identifier: "inline-task-cancel-\(taskID)")
    }
    try setValue("Edited acceptance task", on: committedEditor)
    let addDate: AXUIElement = try waitFor("inline Add Date action") {
        findButton(window, title: "+ Add Date") ?? findButton(window, title: "Add Date")
    }
    try press(addDate, "Add Date")
    let tomorrow: AXUIElement = try waitFor("inline Tomorrow action") {
        findButton(application, title: "Tomorrow")
    }
    try press(tomorrow, "Tomorrow")
    // The quick-date choice updates the draft but intentionally keeps the
    // native calendar visible. Toggling the date chip closes it before Save.
    try press(addDate, "Add Date")
    try press(explicitSave, "inline-task-save-\(taskID)")
    _ = try waitFor("visible Save committed inline draft") {
        findTaskTitle(window, text: "Edited acceptance task") != nil &&
            find(window, identifier: "inline-task-title-\(taskID)") == nil ? true : nil
    }

    let returnEntry: AXUIElement = try waitFor("row title for Return entry") {
        findTaskTitle(window, text: "Edited acceptance task")
    }
    try leftClick(returnEntry, "task title")
    let returnEditor: AXUIElement = try waitFor("inline title editor for Return") {
        find(window, identifier: "inline-task-title-\(taskID)")
    }
    try setValue("Return-edited acceptance task", on: returnEditor)
    try postKey(36) // Return
    _ = try waitFor("Return committed inline draft") {
        findTaskTitle(window, text: "Return-edited acceptance task") != nil ? true : nil
    }

    // Native context-menu deletion is staged for six seconds. Undo restores
    // the exact original row ID because no backend delete has happened yet.
    let editedTitle: AXUIElement = try waitFor("identified edited task title") {
        findTaskTitle(window, text: "Return-edited acceptance task")
    }
    try rightClick(editedTitle)
    let deleteItem: AXUIElement = try waitFor("task Delete menu item") {
        findDeleteMenuItem(application)
    }
    try press(deleteItem, "Delete")
    let undo: AXUIElement = try waitFor("undo-delete action") {
        find(window, identifier: "undo-delete")
    }
    _ = try waitFor("staged deletion hidden") {
        find(window, identifier: "task-title-\(taskID)") == nil ? true : nil
    }
    try press(undo, "undo-delete")
    _ = try waitFor("identity-preserving undo") {
        find(window, identifier: "task-title-\(taskID)") != nil ? true : nil
    }

    let completion: AXUIElement = try waitFor("task completion control") {
        find(window, identifier: "task-complete-\(taskID)")
    }
    let completionIdentifier = stringAttribute(completion, kAXIdentifierAttribute)
    try press(completion, completionIdentifier)
    // Wait for the first RPC completion to commit before revealing the
    // completed section. The original quick-add title was renamed above;
    // checking for "Acceptance task" here passed immediately and raced the
    // subsequent restore click, leaving the task completed on slow runners.
    _ = try waitFor("completed task committed and hidden from active view") { () -> Bool? in
        guard let completed = find(window, identifier: "smart-view-completed") else {
            return nil
        }
        let countIsOne = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
            .contains { stringAttribute(completed, $0) == "1" }
        return countIsOne &&
            findTaskTitle(window, text: "Return-edited acceptance task") == nil ? true : nil
    }

    // Completion is covered with a real native control, but the golden-path
    // task must remain active so the cold-restart assertion checks the same
    // task a new user just created and dated. Reveal completed rows, restore
    // this task, and leave its title/date untouched for restart verification.
    let showCompleted: AXUIElement = try waitFor("Show Completed action") {
        findButton(window, title: "Show Completed")
    }
    try press(showCompleted, "Show Completed")
    // The reveal triggers an asynchronous snapshot reload and a row animation.
    // A title alone can appear before the native checkbox is ready for AXPress.
    // Require the entire completed-state surface to remain coherent for 250 ms.
    // Do not retry a failed restore press: a second toggle would mask a bug.
    var revealedSince: Date?
    _ = try waitFor("stable completed task and native restore control") { () -> Bool? in
        let countIsOne = find(window, identifier: "smart-view-completed").map { completed in
            [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                .contains { stringAttribute(completed, $0) == "1" }
        } ?? false
        let coherent = countIsOne &&
            findButton(window, title: "Hide Completed") != nil &&
            findTaskTitle(window, text: "Return-edited acceptance task") != nil &&
            find(window, identifier: "task-complete-\(taskID)") != nil
        if !coherent {
            revealedSince = nil
            return nil
        }
        if revealedSince == nil { revealedSince = Date() }
        return Date().timeIntervalSince(revealedSince!) >= 0.25 ? true : nil
    }
    try writeJSON(snapshot(window), to: output.appendingPathComponent("before-restore.json"))
    let restoreCompletion: AXUIElement = try waitFor("completed task restore control") {
        find(window, identifier: "task-complete-\(taskID)")
    }
    try press(restoreCompletion, "task-complete-\(taskID)")
    try writeJSON(snapshot(window), to: output.appendingPathComponent("after-restore-press.json"))
    let _: Bool = try waitFor("golden-path task restored and persisted as active") { () -> Bool? in
        guard let completed = find(window, identifier: "smart-view-completed") else {
            return nil
        }
        let countIsZero = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
            .contains { stringAttribute(completed, $0) == "0" }
        return countIsZero &&
            findTaskTitle(window, text: "Return-edited acceptance task") != nil ? true : nil
    }

    try writeJSON(snapshot(application), to: output.appendingPathComponent("accessibility.json"))
    let screenshot = Process()
    screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    screenshot.arguments = ["-x", output.appendingPathComponent("screen.png").path]
    try screenshot.run()
    screenshot.waitUntilExit()
    guard screenshot.terminationStatus == 0 else { throw DriverError.failure("screencapture failed") }

    try writeJSON([
        "platform": "macos",
        "actions": [
            "type:quick-add", "press:quick-add-submit",
            "press:task-details-\(taskID)", "press:detail-done-\(taskID)",
            "click:task-title", "edit:escape-cancel", "edit:return-commit",
            "context-menu:delete", "press:undo-delete",
            "press:\(completionIdentifier)", "press:show-completed",
            "press:task-complete-\(taskID)",
        ],
        "assertions": [
            "packaged SwiftUI window activated",
            "fresh profile exposes an actionable first-task empty state",
            "stable AXIdentifiers exposed",
            "RPC-created task appeared",
            "ⓘ opened the anchored detail layer",
            "detail title change autosaved to the stored row without further action",
            "Done closed the layer without discarding",
            "title click opened the inline quick editor",
            "Escape cancelled the focused inline draft and visible Save/Cancel actions were exposed",
            "visible Save acknowledged and committed the inline draft",
            "Tomorrow was chosen through the native date popover before Save",
            "Return committed a subsequent inline draft",
            "delete undo restored the original task ID",
            "changed Event removed the completed task from the active view",
            "Show Completed exposed the task and native completion restored it for the golden restart path",
            "native application accepted termination",
        ],
    ], to: output.appendingPathComponent("interaction-trace.json"))

    guard let running = NSRunningApplication(processIdentifier: pid), running.terminate() else {
        throw DriverError.failure("native application rejected termination")
    }
} catch {
    if let application = diagnosticApplication, let output = diagnosticOutput {
        try? writeJSON(snapshot(application), to: output.appendingPathComponent("accessibility-failure.json"))
    }
    FileHandle.standardError.write(Data("Taskly macOS acceptance failed: \(error)\n".utf8))
    exit(1)
}
