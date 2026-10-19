import AppKit
import SwiftUI
import Shared
import UniformTypeIdentifiers

/// Main window (v1.1 "Classic Modern") — same layout as git-exclude-manager's PatternsView: the hosts list on the
/// left, a tool window on the right (icon rail, one panel at a time: History · AI Agent · Help, then Appearance · Settings).
/// `/etc/hosts` is the window title and the helper status the subtitle; no toolbar buttons. Liquid Glass on the control layer only (search,
/// buttons, tool window; material before macOS 26). Keyboard: ⌘N add · ⌘F search · Space on/off · ⌫ delete ·
/// Return / double-click edit or rename.
struct HostsView: View {
    @Environment(HostsViewModel.self) private var vm
    @Environment(HelperInstaller.self) private var installer
    @AppStorage("ui.accent") private var storedAccent = AccentChoice.system
    @AppStorage("ui.gradient") private var storedTheme = GradientTheme.none
    /// Open tool-window panel; "" = hidden. First launch (nothing stored) opens AI Agent — its welcome and
    /// suggested questions introduce the app; after that the user's last choice (including hidden) is kept.
    @AppStorage("ui.toolPanel") private var toolPanelRaw = ToolPanel.agent.rawValue
    @AppStorage("app.appearance") private var appearance = Appearance.system
    @State private var showingRawPreview = false
    @FocusState private var isSearchFocused: Bool

    private var accent: AccentChoice {
        AccentChoice.launchOverride ?? GradientTheme.launchOverride?.accent ?? storedAccent
    }
    private var theme: GradientTheme { GradientTheme.launchOverride ?? storedTheme }
    private var toolPanel: Binding<ToolPanel?> {
        Binding(get: { ToolPanel(rawValue: toolPanelRaw) }, set: { toolPanelRaw = $0?.rawValue ?? "" })
    }

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            HStack(spacing: 0) {
                hostsColumn.frame(minWidth: 420)
                ToolWindow(panel: toolPanel, theme: theme, canWrite: canWrite)
            }
            .navigationTitle(HelperConstants.hostsPath)
            .navigationSubtitle(localized(vm.isDemo ? "helper.ready" : installer.statusKey))
        }
        .font(.app(13))
        .tint(accent.color)
        .sheet(item: $vm.editor) { editor in
            EditorSheet(editor: editor, onSave: vm.commitEditor) { vm.editor = nil }
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
        // Here, not in AppearancePanel: the panel may never be opened, and the choice must apply at launch
        .onChange(of: appearance, initial: true) { NSApp.appearance = appearance.nsAppearance }
    }

    // MARK: - Left column

    private var hostsColumn: some View {
        VStack(spacing: 0) {
            if !vm.isDemo && installer.status != .ready {
                HelperBanner().padding([.horizontal, .top], 12)
            }
            controls
            list
            statusBar
        }
        .background(Color(.textBackgroundColor))
    }

    /// Control layer: search capsule + action buttons, glass on macOS 26.
    private var controls: some View {
        @Bindable var vm = vm
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                // Real button so ⌘F works (keyboardShortcut only fires on buttons/controls)
                Button { isSearchFocused = true } label: {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)
                .help(localized("hint.withShortcut", localized("placeholder.search"), "⌘F"))
                TextField(localized("placeholder.search"), text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .accessibilityLabel(localized("placeholder.search"))
                if !vm.searchText.isEmpty {
                    Button { vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localized("btn.clear"))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassSurface(cornerRadius: 16)

            HStack(spacing: 8) {
                Button(action: vm.beginAdd) { Label(localized("btn.add"), systemImage: "plus") }
                    .glassButton(prominent: true)
                    .keyboardShortcut("n")
                    .disabled(!canWrite)
                Group {
                    Button(action: vm.addSection) { Label(localized("btn.addSection"), systemImage: "text.badge.plus") }
                        .help(localized("hint.addSection"))
                        .disabled(!canWrite)
                    Button(action: importFile) { Label(localized("btn.import"), systemImage: "square.and.arrow.down") }
                        .disabled(!canWrite)
                    Button(action: exportFile) { Label(localized("btn.export"), systemImage: "square.and.arrow.up") }
                        .disabled(vm.lines.isEmpty)
                }
                .glassButton()
                Spacer(minLength: 8)
                // Full label when it fits, icon only in a narrow window (the tooltip keeps the name).
                ViewThatFits(in: .horizontal) {
                    previewButton.labelStyle(.titleAndIcon)
                    previewButton.labelStyle(.iconOnly)
                }
            }
            .font(.app(13, .medium))  // button labels don't inherit the root font
            .glassGroup()
        }
        .controlSize(.regular)
        .padding(12)
    }

    private var previewButton: some View {
        Button { showingRawPreview = true } label: {
            Label(localized("btn.previewRaw"), systemImage: "doc.plaintext")
        }
        .help(localized("btn.previewRaw"))
        .glassButton()
        .fixedSize()
    }

    // MARK: - List (content layer: no glass)

    private var list: some View {
        // A new section lands at the bottom: bring it on screen so its heading field can take focus
        ScrollViewReader { proxy in
            rowsList(vm.filteredRows)
                .onChange(of: vm.editingSectionID) { _, id in
                    guard let id else { return }
                    // Rows are lazy: the heading field only exists (and can focus) once it's on screen.
                    // NSTableView scrolls by *estimated* row heights first (rows here differ: header vs entries)
                    // and stops short, so scroll again once the real heights are measured.
                    Task {
                        for _ in 0..<2 {
                            proxy.scrollTo(id, anchor: .bottom)
                            await Task.yield()
                        }
                    }
                }
        }
    }

    private func rowsList(_ rows: [HostsRow]) -> some View {
        @Bindable var vm = vm
        // Native selection: ⌘-click / ⇧-click; dragging any selected row moves all of them (git-exclude-manager).
        return List(selection: $vm.selection) {
            ForEach(rows) { row in
                HostsRowView(
                    row: row,
                    canWrite: canWrite,
                    onEdit: { vm.beginEdit($0) },
                    onToggle: { vm.toggle($0) },
                    onDelete: { vm.delete($0) },
                    onRename: { vm.renameSection($0, to: $1) },
                    isEditingSection: vm.editingSectionID == row.id,
                    onEndEditing: { vm.editingSectionID = nil }
                )
                .listRowSeparator(.hidden)
                // Filtered positions don't map to file order, so reorder only when not searching.
                .moveDisabled(!canWrite || vm.isSearching || row.isSystem)
            }
            .onMove(perform: vm.moveRows)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onDeleteCommand { if canWrite { vm.deleteSelection(in: rows) } }
        .onKeyPress(.space) {
            guard canWrite, !vm.selection.isEmpty else { return .ignored }
            vm.toggleSelection(in: rows)
            return .handled
        }
        // Double-click = primary action (a row-wide tap gesture would swallow the drag).
        .contextMenu(forSelectionType: Int.self) { ids in
            let targets = rows.filter { ids.contains($0.id) }
            if targets.count == 1, case .entry(_, let entry) = targets[0], !entry.isSystem {
                Button(localized("btn.edit")) { vm.beginEdit(entry) }
                Button(localized(entry.isEnabled ? "btn.turnOff" : "btn.turnOn")) { vm.toggle(entry) }
                    .disabled(!canWrite)
                Divider()
            }
            if targets.contains(where: { !$0.isSystem }) {
                Button(localized("btn.delete"), role: .destructive) { vm.delete(targets) }
                    .disabled(!canWrite)
            }
        } primaryAction: { ids in
            // Double-click / Return: edit an entry, rename a section
            guard ids.count == 1, let row = rows.first(where: { ids.contains($0.id) }) else { return }
            switch row {
            case .entry(_, let entry) where !entry.isSystem: vm.beginEdit(entry)
            case .section(let id, _) where canWrite: vm.editingSectionID = id
            default: break
            }
        }
        .overlay { if rows.isEmpty { EntriesEmptyState(canWrite: canWrite) } }
    }

    private var statusBar: some View {
        HStack {
            Text(localized("status.entries", vm.entries.count, vm.enabledCount))
                .font(.app(12))
                .foregroundStyle(.secondary)
            Spacer()
            if vm.isSaving {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
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
}

#Preview {
    HostsView()
        .environment(HostsViewModel(lines: MockData.lines))
        .environment(HelperInstaller())
        .frame(width: 1100, height: 700)
}
