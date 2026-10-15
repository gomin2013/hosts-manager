import Foundation
import Observation
import Shared

/// One row of the list, in file order (same row kinds as git-exclude-manager's pattern list).
enum HostsRow: Identifiable, Equatable {
    /// Blank line, optionally followed by a single `# heading` line (git-exclude-manager convention).
    case section(id: Int, title: String)
    /// Other comment / unknown lines, shown verbatim. `isSystem` = the stock macOS header (not deletable).
    case comment(id: Int, text: String, isSystem: Bool)
    case entry(id: Int, HostEntry)

    /// Index of the row's first line in `HostsViewModel.lines`.
    var id: Int {
        switch self {
        case .section(let id, _), .comment(let id, _, _), .entry(let id, _): id
        }
    }
}

@MainActor
@Observable
final class HostsViewModel {
    var lines: [HostsLine]
    var searchText = ""
    /// Non-nil while the editor sheet is open.
    var editor: EditorViewModel?

    // Phase 2: load from /etc/hosts instead of mock data.
    init(lines: [HostsLine] = MockData.lines) {
        self.lines = lines
    }

    var entries: [HostEntry] {
        lines.compactMap { if case .entry(let entry) = $0 { entry } else { nil } }
    }

    var enabledCount: Int { entries.filter(\.isEnabled).count }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// All rows; while searching, only the entries that match (sections and comments hidden).
    var filteredRows: [HostsRow] {
        let rows = Self.rows(from: lines)
        guard isSearching else { return rows }
        return rows.filter { if case .entry(_, let entry) = $0 { entry.matches(searchText) } else { false } }
    }

    /// What Preview Raw shows — the file as it would be written.
    var rawText: String { HostsLine.serialize(lines) }

    func beginAdd() { editor = EditorViewModel() }

    func beginEdit(_ entry: HostEntry) {
        guard !entry.isSystem else { return }
        editor = EditorViewModel(entry: entry)
    }

    /// Groups lines into rows. A blank line is a section break; if exactly one comment line follows it, that comment
    /// is the section's heading. Any other run of comment / unknown lines becomes one verbatim comment block.
    nonisolated static func rows(from lines: [HostsLine]) -> [HostsRow] {
        var rows: [HostsRow] = []
        var index = 0
        var seenEntry = false

        while index < lines.count {
            switch lines[index] {
            case .blank:
                if case .comment(let heading)? = lines[safe: index + 1], lines[safe: index + 2]?.isCommentLike != true {
                    rows.append(.section(id: index, title: heading.trimmingCharacters(in: .whitespaces)))
                    index += 2
                } else {
                    rows.append(.section(id: index, title: ""))
                    index += 1
                }
            case .comment, .unknown:
                let start = index
                var block: [String] = []
                while let line = lines[safe: index], line.isCommentLike {
                    block.append(line.text)
                    index += 1
                }
                let text = block.joined(separator: "\n")
                // ponytail: "system header" = comment block above the first entry mentioning "Host Database"
                rows.append(.comment(id: start, text: text, isSystem: !seenEntry && text.contains("Host Database")))
            case .entry(let entry):
                seenEntry = true
                rows.append(.entry(id: index, entry))
                index += 1
            }
        }
        return rows
    }
}

private extension HostsLine {
    var isCommentLike: Bool {
        switch self {
        case .comment, .unknown: true
        case .entry, .blank: false
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
