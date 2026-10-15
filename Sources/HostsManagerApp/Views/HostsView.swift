import SwiftUI
import Shared

/// Main window — same layout as git-exclude-manager's PatternsView: toolbar, hosts list on the left,
/// AI Agent + Help panels on the right. Mirrors `.prototype/index.html`.
struct HostsView: View {
    @Environment(HostsViewModel.self) private var vm
    /// Right-column panels fold; remembered across launches (same keys as git-exclude-manager).
    @AppStorage("ui.chatCollapsed") private var chatCollapsed = false
    @AppStorage("ui.helpCollapsed") private var helpCollapsed = true
    @State private var showingRawPreview = false
    @State private var showingAbout = false
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
            EditorSheet(editor: editor) { vm.editor = nil }
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
            // Phase 2: live helper status
            Text(localized("helper.notInstalled"))
                .font(.caption)
                .foregroundStyle(.secondary)
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

            // Phase 2/3: these change /etc/hosts or need file panels.
            Group {
                Button(action: {}, label: { Label(localized("btn.addSection"), systemImage: "text.badge.plus") })
                    .help(localized("hint.addSection"))
                Button(action: {}, label: { Label(localized("btn.import"), systemImage: "arrow.down.doc") })
                Button(action: {}, label: { Label(localized("btn.export"), systemImage: "arrow.up.doc") })
            }
            .buttonStyle(.bordered)
            .disabled(true)

            Spacer()

            Button(action: {}, label: { Label(localized("btn.restore"), systemImage: "arrow.uturn.backward") })
                .buttonStyle(.bordered)
                .disabled(true)
                .help(localized("hint.restore"))

            Button(action: { showingRawPreview = true }, label: {
                Label(localized("btn.previewRaw"), systemImage: "eye")
            })
            .buttonStyle(.bordered)
            .help(localized("btn.previewRaw"))
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .font(.callout)
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
            List(rows) { row in
                HostsRowView(row: row) { vm.beginEdit($0) }
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(localized("status.entries", vm.entries.count, vm.enabledCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

#Preview {
    HostsView().environment(HostsViewModel()).frame(width: 1000, height: 640)
}
