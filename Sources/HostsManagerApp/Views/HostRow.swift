import SwiftUI
import Shared

/// One list row — entry, section break or comment block (same three kinds as git-exclude-manager's PatternRow).
/// v1.1 look: checkbox, data in SF Mono, no cards; edit / delete always shown, in the secondary colour (no wall of red
/// trash cans) — every delete can be undone in History. Not on hover: rows scrolling under a still pointer didn't get
/// hover-exit, so buttons stuck on and the list stuttered.
struct HostsRowView: View {
    let row: HostsRow
    /// False while the helper isn't ready or a save is in flight — toggle / delete are disabled.
    var canWrite = false
    var onEdit: (HostEntry) -> Void = { _ in }
    var onToggle: (HostEntry) -> Void = { _ in }
    var onDelete: (HostsRow) -> Void = { _ in }
    var onRename: (HostsRow, String) -> Void = { _, _ in }
    /// Section rows: heading shown as a focused text field (see `HostsViewModel.editingSectionID`).
    var isEditingSection = false
    var onEndEditing: () -> Void = {}

    var body: some View {
        Group {
            switch row {
            case .entry(_, let entry):
                HostRow(entry: entry, canWrite: canWrite,
                        onEdit: { onEdit(entry) }, onToggle: { onToggle(entry) }, onDelete: { onDelete(row) })
            case .section(_, let title):
                SectionRow(title: title, canWrite: canWrite, isEditing: isEditingSection,
                           onDelete: { onDelete(row) },
                           onRename: { onRename(row, $0) }, onEndEditing: onEndEditing)
            case .comment(_, let text, let isSystem):
                CommentRow(text: text, isSystem: isSystem, canWrite: canWrite) { onDelete(row) }
            }
        }
        .contentShape(Rectangle())
    }
}

/// ✎ / 🗑 at the end of every row.
private struct RowActions: View {
    let name: String
    let canWrite: Bool
    var onEdit: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let onEdit {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .help(localized("btn.edit"))
                    .accessibilityLabel(localized("a11y.editNamed", name))
            }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .disabled(!canWrite)
                .help(localized("btn.delete"))
                .accessibilityLabel(localized("a11y.deleteNamed", name))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

struct HostRow: View {
    let entry: HostEntry
    var canWrite = false
    let onEdit: () -> Void
    var onToggle: () -> Void = {}
    var onDelete: () -> Void = {}

    private var name: String { entry.hostnames.joined(separator: ", ") }

    var body: some View {
        HStack(spacing: 12) {
            Toggle(name, isOn: Binding(get: { entry.isEnabled }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!canWrite || entry.isSystem)
                .help(localized("hint.toggle"))
            Text(entry.ip)
                .font(.data())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)
                .help(entry.ip)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.hostnames.joined(separator: "  ")).font(.data()).lineLimit(1)
                if let comment = entry.comment, !comment.isEmpty {
                    HStack(spacing: 4) {
                        if entry.hasInlineComment {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(localized("hint.inlineComment"))
                                .accessibilityLabel(localized("hint.inlineComment"))
                        }
                        Text(comment)
                    }
                    .font(.app(12))
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if entry.isSystem {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help(localized("hint.system"))
                    .accessibilityLabel(localized("hint.system"))
            } else {
                RowActions(name: name, canWrite: canWrite, onEdit: onEdit, onDelete: onDelete)
            }
        }
        .foregroundStyle(entry.isEnabled ? .primary : .secondary)
        .padding(.vertical, 3)
    }
}

/// Section break: a blank line with an optional `# heading`, marked by an accent bar.
/// The heading is plain text; it turns into a focused field while editing (new section, double-click, Return) —
/// an always-visible TextField never gets focus inside `List(selection:)`, which looked like a frozen row.
private struct SectionRow: View {
    let title: String
    let canWrite: Bool
    let isEditing: Bool
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let onEndEditing: () -> Void

    @FocusState private var isFocused: Bool

    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(.tint).frame(width: 4, height: 14)
                .help(localized("hint.dragSection"))
                .accessibilityHidden(true)
            if isEditing && canWrite {
                TextField(localized("section.placeholder"), text: $text)
                    .textFieldStyle(.plain)
                    .font(.app(13, .semibold))
                    .focused($isFocused)
                    .onAppear { isFocused = true }
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                    .onExitCommand {
                        text = title  // Esc: keep the old heading
                        onEndEditing()
                    }
                    .frame(maxWidth: 320)
                    .accessibilityLabel(localized("section.placeholder"))
            } else {
                Text(title.isEmpty ? localized("section.placeholder") : title)
                    .font(.app(13, .semibold))
                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                    .help(localized("hint.renameSection"))
            }
            Spacer(minLength: 8)
            if !isEditing {
                RowActions(name: title.isEmpty ? localized("section.placeholder") : title, canWrite: canWrite,
                           onDelete: onDelete)
            }
        }
        .padding(.top, 12)
        .onAppear { text = title }
        .onChange(of: title) { _, newTitle in text = newTitle }
    }

    private func commit() {
        guard isEditing else { return }  // Return already committed; this is the focus loss that follows
        onRename(text)
        onEndEditing()
    }
}

/// Verbatim comment lines. The stock macOS header folds away (it's the same on every Mac) and can't be deleted.
private struct CommentRow: View {
    let text: String
    let isSystem: Bool
    let canWrite: Bool
    let onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        if isSystem {
            DisclosureGroup(isExpanded: $isExpanded) {
                Text(text).font(.data(12)).foregroundStyle(.secondary).textSelection(.enabled)
            } label: {
                Text(localized("label.macHeader")).font(.app(12)).foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Text(text)
                    .font(.data(12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RowActions(name: text.components(separatedBy: "\n").first ?? "", canWrite: canWrite,
                           onDelete: onDelete)
            }
        }
    }
}
