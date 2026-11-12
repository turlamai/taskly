import SwiftUI

/// Anchored task-detail layer (DESIGN-TOKENS §Anchored task detail layer,
/// PRODUCT-SPEC §5b): the full-field editor presented from the row's ⓘ
/// button. Persistence is per-field autosave — discrete controls persist as
/// they change, text fields persist when editing ends (Return or focus
/// moving away) plus once more when the layer closes, the native reading of
/// "every change persists as it is made". Closing never discards. A failed
/// save anchors an actionable error to the field and keeps the layer open
/// for retry; the layer closes when its task leaves the current view
/// (AppModel clears `detailTaskID`).
///
/// Reminder offsets (不提醒/准时/提前…) are staged for the A2 slice: they
/// change §9 scheduling semantics in the shared core, so the field is
/// absent here by declared scope, not omission.
struct TaskDetailPopover: View {
    @Environment(AppModel.self) private var model
    let task: RivetTypes.Task
    let onClose: () -> Void

    private enum TextFieldID: Hashable { case title, notes, url }
    private enum Field {
        case completed, title, date, time, priority, tags, subtasks, notes, url, list
    }

    // Editor state is the source of truth while the layer is open; the
    // stored task catches up through per-field saves.
    @State private var title = ""
    @State private var notes = ""
    @State private var url = ""
    @State private var hasDate = false
    @State private var dueDate = Date()
    @State private var hasTime = false
    @State private var dueTime = Date()
    @State private var priority: Int64 = 0
    @State private var tags: [String] = []
    @State private var subtasks: [RivetTypes.Subtask] = []
    @State private var listId: Int64 = 0
    @State private var completed = false
    @State private var tagDraft = ""
    @State private var subtaskDraft = ""
    @State private var saveError: String?
    @State private var errorField: Field?
    @FocusState private var focusedField: TextFieldID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(model.theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headTags
                    completionRow
                    field(model.t("fieldTitle"), .title, titleField)
                    HStack(alignment: .top, spacing: 10) {
                        field(model.t("fieldDate"), .date, dateField)
                        field(model.t("fieldTime"), .time, timeField)
                    }
                    field(model.t("fieldPriority"), .priority, priorityPicker)
                    field(model.t("fieldTags"), .tags, tagSection)
                    field(model.t("fieldSubtasks"), .subtasks, subtaskSection)
                    field(model.t("fieldNotes"), .notes, notesField)
                    field(model.t("fieldUrl"), .url, urlField)
                    field(model.t("fieldList"), .list, listPicker)
                }
                .padding(14)
            }
            Divider().overlay(model.theme.divider)
            actionBar
        }
        .frame(width: 348)
        .frame(maxHeight: 560)
        .background(model.theme.surface)
        .onAppear(perform: loadFromTask)
        // Closing never discards (§5b): a final save covers edits that ended
        // with the close action (Return in a text field, 完成, outside
        // click, Esc) before the layer leaves the hierarchy.
        .onDisappear {
            model.saveDetailTask(updatedTask())
        }
        // Esc closes the layer. The cancel-action shortcut lives on a hidden
        // button so it works regardless of which control owns focus.
        .background {
            Button(model.t("dialogCancel")) { onClose() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.t("dialogTaskDetail"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.theme.onSurface)
            Spacer(minLength: 8)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.theme.tertiaryText)
                    .padding(6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.t("closeDetail"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                model.deleteTasks([task])
                onClose()
            } label: {
                Text(model.t("taskDelete"))
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.danger)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail-delete-\(task.id)")
            Spacer(minLength: 8)
            Text(model.t("detailAutoSaved"))
                .font(.system(size: 11))
                .foregroundStyle(model.theme.tertiaryText)
            Button {
                onClose()
            } label: {
                Text(model.t("detailClose"))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundStyle(model.theme.accentInk)
                    .background(model.theme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("detail-done-\(task.id)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headTags: some View {
        HStack(spacing: 6) {
            badge(listName)
            badge(subtaskCountText)
            Spacer()
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(model.theme.badgeText)
            .background(model.theme.badgeBackground, in: Capsule())
    }

    private var listName: String {
        task.list_name ?? model.t("fieldList")
    }

    private var subtaskCountText: String {
        if subtasks.isEmpty { return model.t("detailNoSubtasksTag") }
        return model.t("subtitleSubtaskCount",
                       subtasks.filter(\.done).count, subtasks.count)
    }

    // MARK: - Fields

    private var completionRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: $completed) {
                Text(model.t("detailCompleted"))
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.secondaryText)
            }
            .toggleStyle(.checkbox)
            .onChange(of: completed) { _, _ in persist(.completed) }
            if errorField == .completed, let saveError {
                errorText(saveError)
            }
        }
    }

    private func field<V: View>(_ label: String, _ field: Field,
                                @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.theme.secondaryText)
            content()
            if errorField == field, let saveError {
                errorText(saveError)
            }
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(model.theme.danger)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func clearButton(_ action: @escaping () -> Void) -> some View {
        Button(model.t("dialogClear"), action: action)
            .font(.system(size: 12))
            .foregroundStyle(model.theme.secondaryText)
            .buttonStyle(.plain)
    }

    /// Text fields persist when editing ends: Return here, or focus moving
    /// to another control — and once more on close via `onDisappear`.
    private var titleField: some View {
        TextField("", text: $title, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 14))
            .focused($focusedField, equals: .title)
            .onSubmit { persist(.title) }
            .onChange(of: focusedField) { old, _ in
                if old == .title { persist(.title) }
            }
            .accessibilityIdentifier("detail-title-\(task.id)")
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker(
                "", selection: dateSelection,
                in: TaskRowView.dateRange, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: dueDate) { _, _ in
                    hasDate = true
                    persist(.date)
                }
            if hasDate {
                // A date-less task cannot retain a time (§5/§7).
                clearButton {
                    hasDate = false
                    hasTime = false
                    persist(.date)
                }
            }
        }
    }

    private var timeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasTime {
                TimePickerControl(selection: timeSelection)
                    .onChange(of: dueTime) { _, _ in persist(.time) }
                clearButton {
                    hasTime = false
                    persist(.time)
                }
            } else {
                addTimeChip
            }
        }
    }

    private var addTimeChip: some View {
        Button {
            hasTime = true
            dueTime = Self.defaultNewTime()
            persist(.time)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                Text(model.t("labelAddTime"))
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(model.theme.tertiaryText)
            .overlay(Capsule().strokeBorder(model.theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var priorityPicker: some View {
        Picker("", selection: $priority) {
            Text(model.t("prioNone")).tag(Int64(0))
            Text(model.t("prioLow")).tag(Int64(1))
            Text(model.t("prioMedium")).tag(Int64(2))
            Text(model.t("prioHigh")).tag(Int64(3))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: priority) { _, _ in persist(.priority) }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tags.isEmpty {
                hint(model.t("detailNoTags"))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text("#\(tag)")
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Button { removeTag(tag) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(model.theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(model.t("removeTag"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(model.theme.badgeText)
                        .background(model.theme.badgeBackground, in: Capsule())
                    }
                }
            }
            TextField(model.t("tagAddPlaceholder"), text: $tagDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit(addTag)
        }
    }

    private var subtaskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if subtasks.isEmpty {
                hint(model.t("detailNoSubtasks"))
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(subtasks.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            Toggle("", isOn: subtaskBinding(index))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            Text(item.text)
                                .font(.system(size: 13))
                                .strikethrough(item.done)
                                .foregroundStyle(
                                    item.done ? model.theme.tertiaryText : model.theme.onSurface)
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            Button { removeSubtask(index) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(model.theme.tertiaryText)
                                    .padding(3)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(model.t("removeSubtask"))
                        }
                    }
                }
            }
            TextField(model.t("subtaskAddPlaceholder"), text: $subtaskDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit(addSubtask)
        }
    }

    private var notesField: some View {
        TextEditor(text: $notes)
            .font(.system(size: 13))
            .frame(minHeight: 64, maxHeight: 96)
            .scrollContentBackground(.hidden)
            .background(model.theme.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(model.theme.inputBorder, lineWidth: 1))
            .focused($focusedField, equals: .notes)
            .onChange(of: focusedField) { old, _ in
                if old == .notes { persist(.notes) }
            }
    }

    private var urlField: some View {
        TextField("https://", text: $url)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))
            .focused($focusedField, equals: .url)
            .onSubmit { persist(.url) }
            .onChange(of: focusedField) { old, _ in
                if old == .url { persist(.url) }
            }
            .accessibilityIdentifier("detail-url-\(task.id)")
    }

    private var listPicker: some View {
        Picker("", selection: $listId) {
            ForEach(model.lists, id: \.id) { list in
                Text(list.name).tag(list.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: listId) { _, _ in persist(.list) }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(model.theme.tertiaryText)
    }

    // MARK: - State plumbing

    private func loadFromTask() {
        title = task.text
        notes = task.notes ?? ""
        url = task.url ?? ""
        if let dateOnly = DateParser.extractDateOnly(task.due_date), !dateOnly.isEmpty {
            hasDate = true
            dueDate = DateParser.asDate(task.due_date)
        }
        if let time = task.due_time, !time.isEmpty {
            hasTime = true
            dueTime = DateParser.asTime(time)
        }
        priority = task.priority
        tags = task.tags
        subtasks = task.subtasks
        listId = task.list_id
        completed = task.completed
    }

    /// Current editor state as a Task. Text emptiness maps to the absent
    /// optional; a date-less task cannot retain a time (§5/§7).
    private func updatedTask() -> RivetTypes.Task {
        let date = hasDate ? DateParser.string(from: dueDate, format: "yyyy-MM-dd") : nil
        let time = (hasDate && hasTime)
            ? DateParser.string(from: dueTime, format: "HH:mm") : nil
        return RivetTypes.Task(
            id: task.id, list_id: listId, list_name: task.list_name,
            text: title, completed: completed, due_date: date, due_time: time,
            notes: notes.isEmpty ? nil : notes, created_at: task.created_at,
            priority: priority, tags: tags, subtasks: subtasks,
            url: url.isEmpty ? nil : url)
    }

    private var dateSelection: Binding<Date> {
        Binding(
            get: { hasDate ? dueDate : Date() },
            set: { dueDate = $0 })
    }

    private var timeSelection: Binding<Date> {
        Binding(
            get: { hasTime ? dueTime : Self.defaultNewTime() },
            set: { dueTime = $0 })
    }

    /// Adding a time starts at the current minute rounded to the nearest 5
    /// (PRODUCT-SPEC §7), matching the inline editor.
    static func defaultNewTime() -> Date {
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let rounded = min(((minute + 2) / 5) * 5, 55)
        return calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: rounded, second: 0, of: now) ?? now
    }

    private func subtaskBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { subtasks[index].done },
            set: {
                subtasks[index].done = $0
                persist(.subtasks)
            })
    }

    private func addTag() {
        let trimmed = tagDraft.trimmingCharacters(in: .whitespaces)
        tagDraft = ""
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        persist(.tags)
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        persist(.tags)
    }

    private func addSubtask() {
        let trimmed = subtaskDraft.trimmingCharacters(in: .whitespaces)
        subtaskDraft = ""
        guard !trimmed.isEmpty else { return }
        subtasks.append(RivetTypes.Subtask(text: trimmed, done: false))
        persist(.subtasks)
    }

    private func removeSubtask(_ index: Int) {
        subtasks.remove(at: index)
        persist(.subtasks)
    }

    /// One write per change (§5b). Success clears any anchored error; a
    /// failure anchors the actionable message to the changed field and the
    /// layer stays open for correction and retry.
    private func persist(_ field: Field) {
        model.saveDetailTask(updatedTask()) { ok, message in
            if ok {
                saveError = nil
                errorField = nil
            } else {
                saveError = message ?? model.t("detailSaveFailed")
                errorField = field
            }
        }
    }
}
