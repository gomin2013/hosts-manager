import SwiftUI
import Shared

/// One list row — entry, section break or comment block (same three kinds as git-exclude-manager's PatternRow).
struct HostsRowView: View {
    let row: HostsRow
    var onEdit: (HostEntry) -> Void = { _ in }

    var body: some View {
        switch row {
        case .entry(_, let entry): HostRow(entry: entry) { onEdit(entry) }
        case .section(_, let title): SectionRow(title: title)
        case .comment(_, let text, let isSystem): CommentRow(text: text, isSystem: isSystem)
        }
    }
}

/// Trash button shared by all row kinds. Phase 2: confirmation dialog + delete.
private struct DeleteButton: View {
    let name: String

    var body: some View {
        Button(role: .destructive, action: {}, label: {
            Image(systemName: "trash").foregroundStyle(.red)
        })
        .buttonStyle(.borderless)
        .disabled(true)
        .help(localized("btn.delete"))
        .accessibilityLabel(localized("btn.delete") + " " + name)
    }
}

struct HostRow: View {
    let entry: HostEntry
    let onEdit: () -> Void

    private var name: String { entry.hostnames.joined(separator: " ") }

    var body: some View {
        HStack(spacing: 12) {
            // Phase 2: toggling writes /etc/hosts.
            Button(action: {}, label: {
                Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.isEnabled ? .green : .gray)
            })
            .buttonStyle(.plain)
            .disabled(true)
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
                    DeleteButton(name: name)
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
        .onTapGesture(count: 2) { onEdit() }
    }
}

/// Section break: a blank line with an optional `# heading`. Phase 2: inline rename + drag.
private struct SectionRow: View {
    let title: String

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
                .disabled(true)
                .accessibilityLabel(localized("section.placeholder"))
            VStack { Divider() }
            DeleteButton(name: title.isEmpty ? localized("btn.addSection") : title)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isSystem {
                DeleteButton(name: text.components(separatedBy: "\n").first ?? "")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}
