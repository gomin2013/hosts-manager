import SwiftUI
import Shared

/// List actions on several rows at once (⌫, Space, context menu) and the row checkbox binding.
extension HostsViewModel {
    /// Checkbox binding — flipping it goes through the normal `toggle` path.
    func isEnabledBinding(_ entry: HostEntry) -> Binding<Bool> {
        Binding(get: { entry.isEnabled }, set: { _ in self.toggle(entry) })
    }

    /// Highest line first so the lower ids stay valid while deleting. System rows are skipped.
    func delete(_ rows: [HostsRow]) {
        for row in rows.sorted(by: { $0.id > $1.id }) where !row.isSystem { delete(row) }
    }

    /// ⌫ on the list.
    func deleteSelection(in rows: [HostsRow]) { delete(rows.filter { selection.contains($0.id) }) }

    /// Space — flips every selected entry.
    func toggleSelection(in rows: [HostsRow]) {
        for case .entry(let id, let entry) in rows where selection.contains(id) && !entry.isSystem { toggle(entry) }
    }
}

#if DEBUG
extension HostsViewModel {
    /// `-demo -editEntry`: opens the editor on api.test — the website's editor screenshot without clicking.
    func openDemoEditor() {
        guard isDemo, CommandLine.arguments.contains("-editEntry"),
              let entry = entries.first(where: { $0.hostnames.contains("api.test") }) else { return }
        beginEdit(entry)
    }

    /// `-demo -demoHistory`: a few in-memory edits so the History panel has steps to show in screenshots —
    /// turn on, pin, turn on, add + name a section, then restore the pin.
    func seedDemoHistory() {
        guard isDemo, CommandLine.arguments.contains("-demoHistory"), history.recent.count == 1,
              let admin = entries.first(where: { $0.hostnames == ["admin.test"] }),
              let staging = entries.first(where: { $0.hostnames == ["staging.example.com"] }) else { return }
        toggle(admin)
        history.pin(rawText, name: "Before staging changes")
        toggle(staging)
        addSection()
        if let row = filteredRows.last { renameSection(row, to: "Kubernetes") }
        editingSectionID = nil
        restore(history.pins[0].text)
    }
}
#endif
