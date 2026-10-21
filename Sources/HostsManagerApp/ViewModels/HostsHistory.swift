import Foundation
import Observation
import Shared

/// What turned the previous state into this one — the History panel's row title (localized by the view).
enum HistoryChange: Equatable, Sendable {
    case earliest, opened
    case turnedOn(String), turnedOff(String)
    case added(String), removed(String), edited(String)
    case sectionAdded(String), sectionRemoved(String), sectionRenamed(String)
    case moved, comments
    case reverted(to: Date?), revertedToPin(String), revertedToOpened
    indirect case several(HistoryChange, more: Int)
}

/// One state of /etc/hosts. `id` is the backup's file name, "current", "opened" or a pin's UUID.
struct HistoryState: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date?
    let text: String
    let change: HistoryChange
}

/// A version the helper backed up: the file as it was until `replacedAt`.
struct ReplacedVersion: Sendable {
    let id: String
    let replacedAt: Date
    let text: String
}

/// A state the user pinned ("Before VPN change"). Kept in the user's Application Support — helper backups are
/// pruned to the newest `HelperConstants.keptBackups`, pins are not.
struct PinnedSnapshot: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var date: Date
    var text: String
}

/// History panel model (Photoshop-style): the last saves read back from the helper's backups, the file as it was
/// when the app opened, and the user's pins. Restoring writes through the normal save path, so a restore is itself
/// a new history step — nothing after it is discarded.
@MainActor
@Observable
final class HostsHistory {
    nonisolated static let shownCount = HelperConstants.keptBackups

    /// Newest first; `recent[0]` is the current file. Steps the user removed are left out.
    private(set) var recent: [HistoryState] = []
    private(set) var pins: [PinnedSnapshot] = []
    /// The file when the app opened — pinned automatically, like Photoshop's opening snapshot.
    private(set) var opened: HistoryState?
    /// Backups the user removed from the list. ponytail: hidden, not deleted — the root helper's backups are
    /// root-owned and pruned at `keptBackups` anyway; add a helper delete call if hiding ever isn't enough.
    private(set) var hidden: Set<String> = []

    /// nil in demo mode: previous states live in `demoReplaced` instead of the helper's Backups folder.
    private let backupsURL: URL?
    private let pinsURL: URL?
    private let hiddenURL: URL?
    private var demoReplaced: [(date: Date, text: String)] = []

    init(backupsURL: URL?, pinsURL: URL?, hiddenURL: URL? = nil) {
        self.backupsURL = backupsURL
        self.pinsURL = pinsURL
        self.hiddenURL = hiddenURL
        if let pinsURL, let data = try? Data(contentsOf: pinsURL) {
            pins = (try? JSONDecoder().decode([PinnedSnapshot].self, from: data)) ?? []
        }
        if let hiddenURL, let data = try? Data(contentsOf: hiddenURL) {
            hidden = (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
        }
    }

    nonisolated static var defaultPinsURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HostsManager/history-pins.json")
    }

    // MARK: - Loading

    /// Re-reads the backups (newest `shownCount + 1`, one extra to title the oldest shown step).
    func reload(current: String) {
        let previous = backupsURL.map(Self.readBackups) ?? demoReplaced.enumerated().map {
            ReplacedVersion(id: "demo-\($0.offset)", replacedAt: $0.element.date, text: $0.element.text)
        }
        if opened == nil {
            opened = HistoryState(id: "opened", date: .now, text: current, change: .earliest)
        }
        // Titles come from the full list (each step diffs with the one before it), then removed steps drop out
        recent = Self.states(previous: Array(previous.suffix(Self.shownCount)), current: current,
                             pins: pins, opened: opened)
            .filter { !hidden.contains($0.id) }
        // Forget removals whose backup the helper has since pruned, so the file stays small
        let existing = Set(previous.map(\.id))
        if !hidden.isSubset(of: existing) {
            hidden.formIntersection(existing)
            save(hidden, to: hiddenURL)
        }
    }

    /// Removes one past step from the list. The current file ("Now") can't be removed.
    func remove(_ id: String) {
        guard id != "current" else { return }
        hidden.insert(id)
        save(hidden, to: hiddenURL)
        recent.removeAll { $0.id == id }
    }

    /// Demo mode: remember the state an edit replaced (the helper's backup does this for real files).
    func recordDemoEdit(replaced text: String) {
        demoReplaced.append((.now, text))
    }

    private nonisolated static func readBackups(_ url: URL) -> [ReplacedVersion] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter { $0.hasPrefix("hosts-") }
            .sorted()
            .suffix(shownCount)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return names.compactMap { name in
            guard let date = formatter.date(from: String(name.dropFirst("hosts-".count))),
                  let data = try? Data(contentsOf: url.appendingPathComponent(name)),
                  let text = String(bytes: data, encoding: .utf8) else { return nil }
            return ReplacedVersion(id: name, replacedAt: date, text: text)
        }
    }

    /// States newest first. A backup is the file *before* a save, stamped with that save's time — so state k was
    /// created when state k-1 was replaced. Titles come from diffing each state with the one before it.
    nonisolated static func states(
        previous: [ReplacedVersion], current: String,
        pins: [PinnedSnapshot] = [], opened: HistoryState? = nil
    ) -> [HistoryState] {
        let all = previous.map { (id: $0.id, text: $0.text) } + [(id: "current", text: current)]
        let dates: [Date?] = [nil] + previous.map(\.replacedAt)
        let result = all.indices.map { index -> HistoryState in
            let text = all[index].text, date = dates[index]
            // "Restored …" only for a state made *after* the version it matches (a pin's own origin is not a restore)
            let isLater = { (other: Date?) in date.flatMap { date in other.map { date > $0 } } ?? false }
            let change: HistoryChange
            if index == 0 {
                change = text == opened?.text ? .opened : .earliest
            } else if let pin = pins.first(where: { $0.text == text && isLater($0.date) }) {
                change = .revertedToPin(pin.name)
            } else if text == opened?.text, all[index - 1].text != text, isLater(opened?.date) {
                change = .revertedToOpened
            } else if let earlier = all[..<(index - 1)].lastIndex(where: { $0.text == text }) {
                change = .reverted(to: dates[earlier])
            } else {
                change = HistoryDiff.change(from: all[index - 1].text, to: text)
            }
            return HistoryState(id: all[index].id, date: date, text: text, change: change)
        }
        return result.reversed()
    }

    // MARK: - Pins

    func pin(_ text: String, name: String) {
        pins.insert(PinnedSnapshot(name: name, date: .now, text: text), at: 0)
        savePins()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[index].name = name
        savePins()
    }

    func unpin(_ id: UUID) {
        pins.removeAll { $0.id == id }
        savePins()
    }

    private func savePins() { save(pins, to: pinsURL) }

    private func save(_ value: some Encodable, to url: URL?) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

/// Names the change between two versions of the file, the way a person would describe the edit.
enum HistoryDiff {
    static func change(from old: String, to new: String) -> HistoryChange {
        let before = HostsParser.parse(old).lines, after = HostsParser.parse(new).lines
        var changes = entryChanges(before, after) + sectionChanges(before, after)
        if changes.isEmpty, old != new {
            let reordered = before.map(\.text).sorted() == after.map(\.text).sorted()
            changes = [reordered ? .moved : .comments]
        }
        guard let first = changes.first else { return .comments }
        return changes.count == 1 ? first : .several(first, more: changes.count - 1)
    }

    private static func entryChanges(_ before: [HostsLine], _ after: [HostsLine]) -> [HistoryChange] {
        let old = entries(before), new = entries(after)
        let oldByKey = Dictionary(old.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        let newKeys = Set(new.map(key))
        var changes: [HistoryChange] = []
        for entry in new {
            guard let previous = oldByKey[key(entry)] else { continue }
            if previous.isEnabled != entry.isEnabled {
                changes.append(entry.isEnabled ? .turnedOn(name(entry)) : .turnedOff(name(entry)))
            } else if previous.comment != entry.comment {
                changes.append(.edited(name(entry)))
            }
        }
        var added = new.filter { oldByKey[key($0)] == nil }
        var removed = old.filter { !newKeys.contains(key($0)) }
        // One entry out and one in, or a pair sharing a hostname, is an edit of that entry
        let single = added.count == 1 && removed.count == 1
        var edited = Set<UUID>()
        for entry in added {
            guard let match = removed.firstIndex(where: {
                single || !Set($0.hostnames).isDisjoint(with: entry.hostnames)
            }) else { continue }
            changes.append(.edited(name(entry)))
            removed.remove(at: match)
            edited.insert(entry.id)
        }
        added.removeAll { edited.contains($0.id) }
        return changes + added.map { .added(name($0)) } + removed.map { .removed(name($0)) }
    }

    private static func sectionChanges(_ before: [HostsLine], _ after: [HostsLine]) -> [HistoryChange] {
        let old = counts(sections(before)), new = counts(sections(after))
        let added = new.filter { $0.value > old[$0.key, default: 0] }.keys.sorted()
        let removed = old.filter { $0.value > new[$0.key, default: 0] }.keys.sorted()
        if added.count == 1, removed.count == 1 { return [.sectionRenamed(added[0])] }
        return added.map { .sectionAdded($0) } + removed.map { .sectionRemoved($0) }
    }

    private static func entries(_ lines: [HostsLine]) -> [HostEntry] {
        lines.compactMap { if case .entry(let entry) = $0 { entry } else { nil } }
    }

    private static func sections(_ lines: [HostsLine]) -> [String] {
        HostsViewModel.rows(from: lines).compactMap { if case .section(_, let title) = $0 { title } else { nil } }
    }

    private static func counts(_ titles: [String]) -> [String: Int] {
        Dictionary(titles.map { ($0, 1) }, uniquingKeysWith: +)
    }

    private static func key(_ entry: HostEntry) -> String { entry.ip + " " + entry.hostnames.joined(separator: " ") }

    private static func name(_ entry: HostEntry) -> String { entry.hostnames.first ?? entry.ip }
}
