import SwiftUI
import Shared

/// One list row — entry, section break or comment block (same three kinds as git-exclude-manager's PatternRow).
struct HostsRowView: View {
    let row: HostsRow
    /// False while the helper isn't ready or a save is in flight — toggle / delete are disabled.
    var canWrite = false
    var onEdit: (HostEntry) -> Void = { _ in }
    var onToggle: (HostEntry) -> Void = { _ in }
    var onDelete: (HostsRow) -> Void = { _ in }
    var onRename: (HostsRow, String) -> Void = { _, _ in }

    var body: some View {
        switch row {
        case .entry(_, let entry):
            HostRow(
                entry: entry, canWrite: canWrite,
                onEdit: { onEdit(entry) }, onToggle: { onToggle(entry) }, onDelete: { onDelete(row) }
            )
        case .section(_, let title):
            SectionRow(
                title: title, canWrite: canWrite, onDelete: { onDelete(row) }, onRename: { onRename(row, $0) }
            )
        case .comment(_, let text, let isSystem):
            CommentRow(text: text, isSystem: isSystem, canWrite: canWrite) { onDelete(row) }
        }
    }
}

/// Trash button shared by all row kinds; the list asks for confirmation before deleting.
private struct DeleteButton: View {
    let name: String
    let canWrite: Bool
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action, label: {
            Image(systemName: "trash").foregroundStyle(.red)
        })
        .buttonStyle(.borderless)
        .disabled(!canWrite)
        .help(localized("btn.delete"))
        .accessibilityLabel(localized("btn.delete") + " " + name)
    }
}

struct HostRow: View {
    let entry: HostEntry
    var canWrite = false
    let onEdit: () -> Void
    var onToggle: () -> Void = {}
    var onDelete: () -> Void = {}

    private var name: String { entry.hostnames.joined(separator: " ") }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle, label: {
                Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.isEnabled ? .green : .gray)
            })
            .buttonStyle(.plain)
            .disabled(!canWrite || entry.isSystem)
            .help(localized("hint.toggle"))
            .accessibilityLabel(localized(entry.isEnabled ? "label.enabled" : "label.disabled") + ": " + name)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(entry.ip)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 140, alignment: .leading)
                    Text(entry.hostnames.joined(separator: "  "))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .strikethrough(!entry.isEnabled)
                .foregroundStyle(entry.isEnabled ? .primary : .secondary)

                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if entry.isSystem {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .help(localized("hint.system"))
                    .accessibilityLabel(localized("hint.system"))
            } else {
                HStack(spacing: 10) {
                    Button(action: onEdit, label: { Image(systemName: "pencil") })
                        .help(localized("btn.edit"))
                        .accessibilityLabel(localized("btn.edit") + " " + name)
                    DeleteButton(name: name, canWrite: canWrite, action: onDelete)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

/// Section break: a blank line with an optional `# heading` the user types inline (saved on Return / focus loss).
private struct SectionRow: View {
    let title: String
    let canWrite: Bool
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @FocusState private var isFocused: Bool

    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help(localized("hint.dragSection"))
                .accessibilityHidden(true)
            TextField(localized("section.placeholder"), text: $text)
                .textFieldStyle(.plain)
                .font(.headline)
                .fixedSize()
                .focused($isFocused)
                .onSubmit { onRename(text) }
                .onChange(of: isFocused) { _, focused in if !focused { onRename(text) } }
                .disabled(!canWrite)
                .accessibilityLabel(localized("section.placeholder"))
            VStack { Divider() }
            DeleteButton(
                name: title.isEmpty ? localized("btn.addSection") : title, canWrite: canWrite, action: onDelete
            )
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .padding(.horizontal, 12)
        .onAppear { text = title }
        .onChange(of: title) { _, newTitle in text = newTitle }
    }
}

/// Verbatim comment lines (e.g. the macOS header) — read-only; the system header can't be deleted.
private struct CommentRow: View {
    let text: String
    let isSystem: Bool
    let canWrite: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isSystem {
                DeleteButton(
                    name: text.components(separatedBy: "\n").first ?? "", canWrite: canWrite, action: onDelete
                )
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}
