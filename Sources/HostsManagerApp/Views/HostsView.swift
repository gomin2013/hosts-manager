import AppKit
import SwiftUI
import Shared
import UniformTypeIdentifiers

/// Main window — same layout as git-exclude-manager's PatternsView: toolbar, hosts list on the left,
/// AI Agent + Help panels on the right. Mirrors `.prototype/index.html`.
struct HostsView: View {
    @Environment(HostsViewModel.self) private var vm
    @Environment(HelperInstaller.self) private var installer
    /// Right-column panels fold; remembered across launches (same keys as git-exclude-manager).
    @AppStorage("ui.chatCollapsed") private var chatCollapsed = false
    @AppStorage("ui.helpCollapsed") private var helpCollapsed = true
    @State private var showingRawPreview = false
    @State private var showingAbout = false
    @State private var pendingDelete: HostsRow?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            toolbar
            HSplitView {
                hostsPanel
                    .frame(minWidth: 400)
                VStack(spacing: 0) {
                    ChatPanel(hostsText: vm.rawText, isCollapsed: $chatCollapsed)
                    Divider()
                    HelpPanel(isCollapsed: $helpCollapsed)
                    // Nothing expanded that can grow: keep the headers at the top
                    if chatCollapsed && helpCollapsed {
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: 340)
            }
        }
        .sheet(item: $vm.editor) { editor in
            EditorSheet(editor: editor, onSave: vm.commitEditor) { vm.editor = nil }
        }
        .alert(
            localized("confirm.deleteTitle"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { row in
            Button(localized("btn.delete"), role: .destructive) { vm.delete(row) }
            Button(localized("btn.cancel"), role: .cancel) {}
        } message: { row in
            Text(localized("confirm.deleteMessage", Self.deleteName(row)))
        }
        // Import: merge or replace
        .confirmationDialog(
            localized("dialog.importTitle"),
            isPresented: Binding(get: { vm.pendingImport != nil }, set: { if !$0 { vm.pendingImport = nil } })
        ) {
            Button(localized("btn.merge")) { vm.applyImport(replace: false) }
            Button(localized("btn.replace"), role: .destructive) { vm.applyImport(replace: true) }
            Button(localized("btn.cancel"), role: .cancel) {}
        } message: {
            Text(localized("dialog.importConfirm", vm.pendingImportCount))
        }
        .alert(
            localized("err.title"),
            isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })
        ) {
            Button(localized("btn.ok"), role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        // The user approves the helper in System Settings, then comes back; also pick up outside edits.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            installer.refresh()
            if !vm.isSaving { vm.load() }
        }
        .sheet(isPresented: $showingRawPreview) {
            RawPreviewView(content: vm.rawText) { showingRawPreview = false }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView { showingAbout = false }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(localized("app.title")).font(.headline)
                Spacer()
                SettingsMenu { showingAbout = true }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.windowBackgroundColor))
            Divider()
        }
    }

    // MARK: - Hosts Panel (left column)

    private var hostsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileInfoBlock
            Divider()
            searchRow
            actionRow
            Divider()
            list
            Divider()
            statusBar
        }
    }

    private var fileInfoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(HelperConstants.hostsPath)
                .font(.headline)
            HStack(spacing: 6) {
                Circle()
                    .fill(installer.status == .ready ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(localized(installer.statusKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if installer.status == .requiresApproval {
                    Button(localized("helper.openSettings"), action: installer.openLoginItems)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var searchRow: some View {
        @Bindable var vm = vm
        return HStack(spacing: 8) {
            // Real button so ⌘F works (keyboardShortcut only fires on buttons/controls)
            Button(action: { isSearchFocused = true }, label: {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            })
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .help(localized("placeholder.search") + " (⌘F)")

            TextField(localized("placeholder.search"), text: $vm.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityLabel(localized("placeholder.search"))

            if !vm.searchText.isEmpty {
                Button(action: { vm.searchText = "" }, label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                })
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: { vm.beginAdd() }, label: {
                Label(localized("btn.add"), systemImage: "plus.circle")
            })
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!canWrite)

            Group {
                Button(action: vm.addSection, label: {
                    Label(localized("btn.addSection"), systemImage: "text.badge.plus")
                })
                .help(localized("hint.addSection"))
                Button(action: importFile, label: { Label(localized("btn.import"), systemImage: "arrow.down.doc") })
            }
            .buttonStyle(.bordered)
            .disabled(!canWrite)

            Button(action: exportFile, label: { Label(localized("btn.export"), systemImage: "arrow.up.doc") })
                .buttonStyle(.bordered)
                .disabled(vm.lines.isEmpty)

            Spacer()

            // Full labels when they fit, icons only in a narrow window (tooltips keep the names).
            ViewThatFits(in: .horizontal) {
                trailingButtons.labelStyle(.titleAndIcon)
                trailingButtons.labelStyle(.iconOnly)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .font(.callout)
    }

    private var trailingButtons: some View {
        HStack(spacing: 8) {
            Button(action: vm.restorePrevious, label: {
                Label(localized("btn.restore"), systemImage: "arrow.uturn.backward")
            })
            .disabled(!canWrite || !vm.canRestore)
            .help(localized(!vm.canRestore ? "hint.noBackup" : "hint.restore"))

            Button(action: { showingRawPreview = true }, label: {
                Label(localized("btn.previewRaw"), systemImage: "eye")
            })
            .help(localized("btn.previewRaw"))
        }
        .buttonStyle(.bordered)
        .fixedSize()
    }

    @ViewBuilder
    private var list: some View {
        let rows = vm.filteredRows
        if rows.isEmpty {
            Text(localized("empty.noResults", vm.searchText))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            @Bindable var vm = vm
            // Native selection: ⌘-click / ⇧-click; dragging any selected row moves all of them (git-exclude-manager).
            List(selection: $vm.selection) {
                ForEach(rows) { row in
                    HostsRowView(
                        row: row,
                        canWrite: canWrite,
                        onEdit: { vm.beginEdit($0) },
                        onToggle: { vm.toggle($0) },
                        onDelete: { pendingDelete = $0 },
                        onRename: { vm.renameSection($0, to: $1) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
                    // Filtered positions don't map to file order, so reorder only when not searching.
                    .moveDisabled(!canWrite || vm.isSearching || row.isSystem)
                }
                .onMove(perform: vm.moveRows)
            }
            .listStyle(.plain)
            // Double-click = primary action (a row-wide tap gesture would swallow the drag).
            .contextMenu(forSelectionType: Int.self) { ids in
                if let row = Self.single(ids, in: rows) {
                    if case .entry(_, let entry) = row, !entry.isSystem {
                        Button(localized("btn.edit")) { vm.beginEdit(entry) }
                    }
                    if !row.isSystem {
                        Button(localized("btn.delete"), role: .destructive) { pendingDelete = row }
                            .disabled(!canWrite)
                    }
                }
            } primaryAction: { ids in
                if case .entry(_, let entry)? = Self.single(ids, in: rows) { vm.beginEdit(entry) }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(localized("status.entries", vm.entries.count, vm.enabledCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if vm.isSaving {
                ProgressView().scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - File panels

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), let text = String(bytes: data, encoding: .utf8) else {
            vm.errorMessage = localized("err.readFailed", url.path)
            return
        }
        vm.beginImport(text)
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "hosts.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try vm.export(to: url)
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    /// Writes need the approved helper and no save in flight.
    private var canWrite: Bool { (installer.status == .ready || vm.isDemo) && !vm.isSaving }

    /// The row when exactly one is targeted by a right-click / double-click.
    private static func single(_ ids: Set<Int>, in rows: [HostsRow]) -> HostsRow? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return rows.first { $0.id == id }
    }

    private static func deleteName(_ row: HostsRow) -> String {
        switch row {
        case .entry(_, let entry): "\(entry.ip) \(entry.hostnames.joined(separator: " "))"
        case .section(_, let title): title.isEmpty ? localized("btn.addSection") : "# \(title)"
        case .comment(_, let text, _): text.components(separatedBy: "\n").first ?? ""
        }
    }
}

#Preview {
    HostsView()
        .environment(HostsViewModel(lines: MockData.lines))
        .environment(HelperInstaller())
        .frame(width: 1000, height: 640)
}
