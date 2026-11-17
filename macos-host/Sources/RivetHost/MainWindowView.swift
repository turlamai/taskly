import AppKit
import SwiftUI

/// Root window: [sidebar | task pane] + status bar (PRODUCT-SPEC §2).
struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.launchState == .none {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        if model.isSidebarVisible {
                            SidebarView()
                                .frame(width: Palette.sidebarWidth)
                            Divider()
                                .overlay(model.theme.divider)
                        }
                        TaskPaneView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider().overlay(model.theme.divider)
                    statusBar
                }
            } else {
                // §2a: the welcome / recovery gate replaces the task UI
                // entirely while no database is open.
                DatabaseGateView()
            }
        }
        .background(model.theme.background)
        .frame(minWidth: 760, minHeight: 520)
        .sheet(item: Binding(
            get: { model.listEditSheet },
            set: { model.listEditSheet = $0 })) { context in
            ListEditSheet(context: context)
        }
        .sheet(item: Binding(
            get: { model.databaseSheet },
            set: { model.databaseSheet = $0 })) { context in
            DatabaseSheetView(context: context)
        }
        .sheet(isPresented: Binding(
            get: { model.aboutVisible },
            set: { model.aboutVisible = $0 })) {
            AboutSheet()
        }
        .sheet(isPresented: Binding(
            get: { model.updateSheetVisible },
            set: { newValue in
                model.updateSheetVisible = newValue
                if !newValue { model.dismissUpdateSheet() }
            })) {
            UpdateSheet()
        }
        .confirmationDialog(
            model.confirmContext?.title ?? "",
            isPresented: Binding(
                get: { model.confirmContext != nil },
                set: { if !$0 { model.confirmContext = nil } }),
            titleVisibility: .visible
        ) {
            Button(model.t("dialogConfirm"), role: .destructive) {
                model.confirmContext?.onConfirm()
                model.confirmContext = nil
            }
            Button(model.t("dialogCancel"), role: .cancel) {
                model.confirmContext = nil
            }
        } message: {
            Text(model.confirmContext?.message ?? "")
        }
        // An alert rather than a confirmationDialog: the dialog's attached
        // buttons never report AX position/action, which locked both the
        // e2e driver and assistive tooling out of the confirmation.
        .alert(
            model.t("dbRestorePreviewTitle"),
            isPresented: Binding(
                get: { model.restoreConfirmation != nil },
                set: { if !$0 { model.restoreConfirmation = nil } })
        ) {
            // The default action is explicit: alert button order alone
            // does not pin which one owns Return, and the restore flow
            // (e2e and assistive tech alike) drives the confirmation with
            // the keyboard.
            Button(model.t("dbRestoreApply"), role: .destructive) {
                model.restoreConfirmation.map { model.confirmRestore($0) }
                model.restoreConfirmation = nil
            }
            .keyboardShortcut(.defaultAction)
            Button(model.t("dialogCancel"), role: .cancel) {
                model.restoreConfirmation = nil
            }
        } message: {
            if let restore = model.restoreConfirmation {
                Text(model.t("dbRestorePreviewBody", restore.taskCount, restore.listCount))
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(model.statusMessage)
                .font(.system(size: 12))
                .foregroundStyle(model.theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: Palette.statusHeight)
        .background(model.theme.sidebar)
    }
}

/// 2×2 smart-view tiles + My Lists section + database identity footer
/// (PRODUCT-SPEC §3, §2a).
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    smartTiles
                    myLists
                }
                .padding(12)
            }
            databaseIdentity
        }
        .background(model.theme.sidebar)
    }

    /// §2a sidebar footer: the database display name plus the
    /// managed-by-you note (prototype `database-identity`).
    private var databaseIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.databaseName.isEmpty
                 ? model.t("dbCurrentNone") : model.databaseName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.theme.onSurface)
                .lineLimit(1)
            Text(model.t("sidebarDbManaged"))
                .font(.system(size: 12))
                .foregroundStyle(model.theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Divider().overlay(model.theme.divider)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("database-identity")
    }

    private var smartTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            SmartChip(view: .today, icon: "calendar", titleKey: "navToday",
                      color: Palette.today, count: Int(model.counts.today))
            SmartChip(view: .planned, icon: "calendar.badge.clock", titleKey: "navPlanned",
                      color: Palette.planned, count: Int(model.counts.planned))
            SmartChip(view: .all, icon: "tray.full", titleKey: "navAll",
                      color: Palette.all, count: Int(model.counts.all))
            SmartChip(view: .completed, icon: "checkmark.circle", titleKey: "navCompleted",
                      color: Palette.all, count: Int(model.counts.completed))
        }
    }

    private var myLists: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.t("sectionMyLists"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.theme.secondaryText)
                Spacer()
                Button {
                    model.listEditSheet = ListEditContext(mode: .create)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(model.theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.isConnected)
                .help(model.t("dialogCreateList"))
            }
            .padding(.horizontal, 4)

            ForEach(model.lists, id: \.id) { list in
                ListRowView(list: list)
            }
        }
    }
}

/// Smart-view chip (DESIGN-TOKENS: 34px neutral chip, radius 8, 8px gaps;
/// colored 14px SF Symbol glyph + 13px label + quiet 12px count right;
/// checked = quiet selection fill, hover = hover fill — saturated color
/// never fills the chip, it lives on the glyph).
private struct SmartChip: View {
    @Environment(AppModel.self) private var model
    let view: SmartView
    let icon: String
    let titleKey: String
    let color: Color
    let count: Int

    @State private var isHovering = false

    private var isSelected: Bool {
        model.currentView == view
    }

    var body: some View {
        Button {
            model.select(view)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(model.t(titleKey))
                    .font(.system(size: 13))
                    .foregroundStyle(model.theme.onSurface)
                    .lineLimit(1)
                    // The label compresses last: Spacer and count yield first.
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 12))
                    .foregroundStyle(model.theme.secondaryText)
                    // One line, never compressed: a count like 13 otherwise
                    // wraps into vertically stacked digits ("1"/"3") because
                    // the label takes its ideal width first. The count wins
                    // the space; the label truncates instead.
                    .lineLimit(1)
                    .layoutPriority(2)
                    .accessibilityIdentifier("smart-count-\(view.backendView)")
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: Palette.smartChipHeight)
            // First background = top layer: the quiet tint composites over
            // the surface fill; border sits outside both.
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? model.theme.selection : (isHovering ? model.theme.hover : .clear)))
            .background(model.theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(model.theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        // SwiftUI combines a Button's label subtree into one AX element on
        // macOS, so expose the visible count on that real actionable node as
        // well as keeping the Text identifier for visual hierarchy tooling.
        .accessibilityIdentifier("smart-view-\(view.backendView)")
        .accessibilityLabel(Text(model.t(titleKey)))
        .accessibilityValue(Text("\(count)"))
        .disabled(!model.isConnected)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct ListRowView: View {
    @Environment(AppModel.self) private var model
    let list: RivetTypes.TodoList

    private var isSelected: Bool {
        model.currentView.listId == list.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(argb: list.color))
                .frame(width: 20, height: 20)
                .overlay(
                    Text(list.icon ?? list.defaultIcon)
                        .font(.system(size: 11))
                        .clipShape(Circle())
                )
            Text(list.name)
                .font(.system(size: 13))
                .foregroundStyle(model.theme.onSurface)
                .lineLimit(1)
            Spacer()
            if list.pending_count > 0 {
                Text("\(list.pending_count)")
                    .font(.system(size: 11))
                    .foregroundStyle(model.theme.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // First background = top layer: selection tint over the surface card.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? model.theme.selection : Color.clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(model.theme.surface)
        )
        .overlay(
            // Checked = quiet selection fill; the divider border never
            // changes color (DESIGN-TOKENS list row).
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(model.theme.divider, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            model.select(.list(list.id))
        }
        .onTapGesture(count: 2) {
            // Reminders: double-click a list renames it in place.
            model.listEditSheet = ListEditContext(mode: .edit(list))
        }
        .contextMenu {
            Button(model.t("dialogEditList")) {
                model.listEditSheet = ListEditContext(mode: .edit(list))
            }
            Button(model.t("listDelete"), role: .destructive) {
                model.confirmContext = ConfirmContext(
                    title: model.t("listDeleteConfirm"),
                    message: model.t("listDeleteConfirmContent"),
                    onConfirm: { model.deleteList(list) })
            }
        }
    }
}
