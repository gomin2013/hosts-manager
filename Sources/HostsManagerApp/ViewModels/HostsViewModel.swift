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
    /// The file as last read (or as changed by the user, while a save is in flight).
    private(set) var file: HostsFile
    var searchText = "" {
        didSet { if searchText != oldValue { selection = [] } }
    }
    /// Selected row ids (⌘-click / ⇧-click). Ids are line positions, so anything that adds or removes lines clears
    /// it; a move re-selects the moved rows at their new positions.
    var selection = Set<Int>()
    /// Non-nil while the editor sheet is open.
    var editor: EditorViewModel?
    /// Localized message for the last failed load/save; the view shows it in an alert.
    var errorMessage: String?
    private(set) var isSaving = false
    /// Lines read from an import file, waiting for the user to pick Merge or Replace.
    var pendingImport: [HostsLine]?

    private let hostsURL: URL
    private let backupsURL: URL
    /// Previews, tests and `-demo` screenshots: fixed lines, never read from or written to disk.
    private let isDemo: Bool
    private let xpc: XPCService
    /// SHA-256 of the file on disk the current `file` is based on; the helper refuses to overwrite anything else.
    private var diskHash = Data().sha256Hex

    /// Production: reads `/etc/hosts`, writes through the helper.
    init(
        hostsURL: URL = URL(fileURLWithPath: HelperConstants.hostsPath),
        backupsURL: URL = URL(fileURLWithPath: HelperConstants.backupsPath, isDirectory: true),
        xpc: XPCService = XPCService()
    ) {
        self.hostsURL = hostsURL
        self.backupsURL = backupsURL
        self.xpc = xpc
        self.isDemo = false
        self.file = HostsFile()
        load()
    }

    /// Previews / tests: fixed lines, nothing read or written.
    init(lines: [HostsLine]) {
        self.hostsURL = URL(fileURLWithPath: "/dev/null")
        self.backupsURL = URL(fileURLWithPath: "/dev/null")
        self.xpc = XPCService()
        self.isDemo = true
        self.file = HostsFile(lines: lines)
    }

    var lines: [HostsLine] { file.lines }

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

    /// What Preview Raw shows — the file exactly as it will be written.
    var rawText: String { file.text }

    // MARK: - Load / save

    /// `/etc/hosts` is world-readable, so the app reads it itself; only writes need the helper.
    func load() {
        guard !isDemo else { return }
        // Not UTF-8 → refuse rather than silently replace bytes and write them back mangled.
        guard let data = try? Data(contentsOf: hostsURL), let text = String(bytes: data, encoding: .utf8) else {
            errorMessage = localized("err.readFailed", hostsURL.path)
            return
        }
        let parsed = HostsParser.parse(text)
        if parsed.text != file.text { selection = [] }
        file = parsed
        diskHash = data.sha256Hex
    }

    // ponytail: one save at a time (mutations are ignored while saving); queue them if users hit it
    /// Applies `change` locally, then writes the whole file through the helper. On failure the file is re-read so
    /// the list always shows what's really on disk.
    private func mutate(_ change: (inout [HostsLine]) -> Void) {
        mutateFile { change(&$0.lines) }
    }

    private func mutateFile(_ change: (inout HostsFile) -> Void) {
        guard !isSaving, !isDemo else { return }
        let before = file
        change(&file)
        guard file != before else { return }
        if file.lines.count != before.lines.count { selection = [] }
        let content = file.text, expected = diskHash
        isSaving = true
        Task {
            do {
                try await xpc.writeHosts(content, expectedSHA256: expected)
                diskHash = Data(content.utf8).sha256Hex
            } catch {
                errorMessage = localized((error as? HelperError)?.localizationKey ?? "err.writeFailed")
                load()
            }
            isSaving = false
        }
    }

    // MARK: - Editing

    func beginAdd() { editor = EditorViewModel() }

    func beginEdit(_ entry: HostEntry) {
        guard !entry.isSystem else { return }
        editor = EditorViewModel(entry: entry)
    }

    /// Save from the editor sheet: replaces the edited entry in place, or appends a new one.
    func commitEditor() {
        guard let editor, let entry = editor.makeEntry() else { return }
        self.editor = nil
        mutate { lines in
            if let index = lines.firstIndex(where: { $0.entryID == entry.id }) {
                lines[index] = .entry(entry)
            } else {
                lines.append(.entry(entry))
            }
        }
    }

    func toggle(_ entry: HostEntry) {
        guard !entry.isSystem else { return }
        mutate { lines in
            guard let index = lines.firstIndex(where: { $0.entryID == entry.id }),
                  case .entry(var changed) = lines[index] else { return }
            changed.isEnabled.toggle()
            lines[index] = .entry(changed)
        }
    }

    /// Removes the row's lines. System entries and the macOS header can't be deleted.
    func delete(_ row: HostsRow) {
        switch row {
        case .entry(_, let entry) where entry.isSystem: return
        case .comment(_, _, true): return
        default: break
        }
        let range = Self.lineRange(of: row, in: lines)
        mutate { $0.removeSubrange(range) }
    }

    // MARK: - Sections & ordering

    /// Section button: a blank line at the end; the user drags it into place and types a heading.
    func addSection() {
        mutate { $0.append(.blank) }
    }

    /// Heading = one `# heading` line after the section's blank line; an empty title removes it.
    func renameSection(_ row: HostsRow, to title: String) {
        guard case .section(_, let old) = row else { return }
        let title = title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard title != old else { return }
        let range = Self.lineRange(of: row, in: lines)
        mutate { $0.replaceSubrange(range, with: [.blank] + (title.isEmpty ? [] : [.comment(" " + title)])) }
    }

    /// `List.onMove` offsets are row positions — one row, or every selected row at once (multi-select drag); each
    /// row moves with all its lines and keeps its order. System rows never move. Not while searching.
    func moveRows(from source: IndexSet, to destination: Int) {
        guard !isSearching, !isSaving else { return }
        let rows = Self.rows(from: lines)
        let movable = IndexSet(source.filter { rows.indices.contains($0) && !rows[$0].isSystem })
        guard !movable.isEmpty else { return }
        let insertAt = destination - movable.filter { $0 < destination }.count
        mutate { lines in
            var chunks = rows.map { Array(lines[Self.lineRange(of: $0, in: lines)]) }
            let moving = movable.map { chunks[$0] }
            for index in movable.sorted(by: >) { chunks.remove(at: index) }
            chunks.insert(contentsOf: moving, at: insertAt)
            lines = chunks.flatMap { $0 }
        }
        // ponytail: row positions = chunk positions, so the moved rows are rows insertAt..<insertAt+count
        let moved = Self.rows(from: lines)
        selection = Set((insertAt..<min(insertAt + movable.count, moved.count)).map { moved[$0].id })
    }

    // MARK: - Import / export / restore

    /// Export writes the file exactly as Preview Raw shows it.
    func export(to url: URL) throws {
        try Data(rawText.utf8).write(to: url, options: .atomic)
    }

    /// Parses an import file; the view then asks Merge or Replace. Imported system entries / header are ignored.
    func beginImport(_ text: String) {
        let imported = HostsParser.parse(text).lines
        let rows = Self.rows(from: imported).filter { !$0.isSystem }
        pendingImport = rows.flatMap { imported[Self.lineRange(of: $0, in: imported)] }
    }

    var pendingImportCount: Int {
        pendingImport?.filter { if case .entry = $0 { true } else { false } }.count ?? 0
    }

    /// Merge appends entries this file doesn't have (same IP + hostnames); Replace keeps only this file's system
    /// header + system entries, then the imported lines.
    func applyImport(replace: Bool) {
        guard let imported = pendingImport else { return }
        pendingImport = nil
        mutate { lines in
            if replace {
                let system = Self.rows(from: lines).filter(\.isSystem)
                    .flatMap { lines[Self.lineRange(of: $0, in: lines)] }
                lines = system + [.blank] + imported
            } else {
                var known = Set(lines.compactMap(\.entryKey))
                for line in imported {
                    guard let key = line.entryKey, known.insert(key).inserted else { continue }
                    lines.append(line)
                }
            }
        }
    }

    /// The newest backup the helper made (the file before the last save), if any.
    var latestBackupURL: URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path)) ?? []
        return names.filter { $0.hasPrefix("hosts-") }.max().map { backupsURL.appendingPathComponent($0) }
    }

    /// Writes the newest backup back. That write backs up the current file first, so clicking again undoes it.
    func restorePrevious() {
        guard let url = latestBackupURL, let data = try? Data(contentsOf: url),
              let text = String(bytes: data, encoding: .utf8) else {
            errorMessage = localized("hint.noBackup")
            return
        }
        mutateFile { $0 = HostsParser.parse(text) }
    }

    /// Lines a row covers — same grouping as `rows(from:)`.
    nonisolated static func lineRange(of row: HostsRow, in lines: [HostsLine]) -> Range<Int> {
        let start = row.id
        switch row {
        case .entry: return start..<start + 1
        case .section:
            return start..<start + (hasHeading(lines, afterBlank: start) ? 2 : 1)
        case .comment:
            var end = start
            while lines[safe: end]?.isCommentLike == true { end += 1 }
            return start..<end
        }
    }

    /// A section's heading is exactly one comment line right after its blank line.
    nonisolated static func hasHeading(_ lines: [HostsLine], afterBlank index: Int) -> Bool {
        guard case .comment? = lines[safe: index + 1] else { return false }
        return lines[safe: index + 2]?.isCommentLike != true
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
                if hasHeading(lines, afterBlank: index), case .comment(let heading) = lines[index + 1] {
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

extension HostsRow {
    /// macOS header block or a system entry — never deleted, moved or replaced.
    var isSystem: Bool {
        switch self {
        case .comment(_, _, let isSystem): isSystem
        case .entry(_, let entry): entry.isSystem
        case .section: false
        }
    }
}

private extension HostsLine {
    /// Identity for Merge: same IP + same set of hostnames, enabled or not.
    var entryKey: String? {
        guard case .entry(let entry) = self else { return nil }
        return entry.ip + " " + entry.hostnames.sorted().joined(separator: " ")
    }

    var entryID: UUID? {
        if case .entry(let entry) = self { entry.id } else { nil }
    }

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
