import SwiftUI

/// History (Photoshop-style): pinned versions on top — the user's pins and the file as it was when the app opened —
/// then the last saves, newest first, each named after what changed. Restore writes that version back; the restore
/// is itself a new step, so nothing is lost. Replaces the single-step Restore Previous button.
struct HistoryPanel: View {
    @Environment(HostsViewModel.self) private var vm
    @Binding var isCollapsed: Bool
    /// False while the helper isn't ready or a save is in flight.
    var canWrite = true
    var panelBackground = Color(.windowBackgroundColor)
    /// Shown alone in a tool window (redesign D): no fold header — the window has its own title.
    var isToolWindow = false

    @State private var renaming: PinnedSnapshot?
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !isToolWindow { CollapseToggle(title: localized("history.title"), isCollapsed: $isCollapsed) }
                Spacer()
                Button { pin(vm.rawText) } label: { Image(systemName: "pin") }
                    .buttonStyle(.borderless)
                    .help(localized("history.pin"))
                    .accessibilityLabel(localized("history.pin"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, isToolWindow ? 2 : 10)

            if !isCollapsed {
                list
            }
        }
        .background(panelBackground)
        .alert(localized("history.renameTitle"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField(localized("history.pinName"), text: $newName)
            Button(localized("btn.save")) {
                if let renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    vm.history.rename(renaming.id, to: newName)
                }
            }
            Button(localized("btn.cancel"), role: .cancel) {}
        }
    }

    private var list: some View {
        List {
            Section(localized("history.pinned")) {
                ForEach(vm.history.pins) { pin in
                    row(Item(id: pin.id.uuidString, icon: "pin.fill", title: pin.name, date: pin.date, text: pin.text,
                        isCurrent: pin.text == vm.rawText))
                        .contextMenu {
                            restoreButton(pin.text)
                            Button(localized("history.rename")) {
                                newName = pin.name
                                renaming = pin
                            }
                            Button(localized("history.unpin")) { vm.history.unpin(pin.id) }
                        }
                }
                if let opened = vm.history.opened {
                    row(Item(id: opened.id, icon: "doc", title: localized("history.opened"), date: opened.date,
                        text: opened.text, isCurrent: opened.text == vm.rawText))
                        .contextMenu { restoreButton(opened.text) }
                }
            }
            Section(localized("history.recent")) {
                ForEach(vm.history.recent) { state in
                    // Only the newest step is "Now"; an older step with the same text is a past version of it
                    let isCurrent = state.id == "current"
                    row(Item(id: state.id, icon: isCurrent ? "largecircle.fill.circle" : "circle",
                        title: Self.title(state.change), date: state.date, text: state.text,
                        isCurrent: isCurrent, onRemove: isCurrent ? nil : { vm.history.remove(state.id) }))
                        .contextMenu {
                            restoreButton(state.text)
                            Button(localized("history.pinThis")) { pin(state.text) }
                            if !isCurrent {
                                Divider()
                                Button(localized("history.remove"), role: .destructive) { vm.history.remove(state.id) }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: .infinity)
    }

    /// One History row's content.
    private struct Item {
        let id: String, icon: String, title: String
        let date: Date?
        let text: String
        let isCurrent: Bool
        /// Shows a trash button; nil for rows that can't be removed ("Now", "When Opened").
        var onRemove: (() -> Void)?
    }

    private func row(_ item: Item) -> some View {
        let id = item.id, text = item.text, isCurrent = item.isCurrent
        return HStack(spacing: 8) {
            Image(systemName: item.icon)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1).fontWeight(isCurrent ? .semibold : .regular)
                if let date = item.date {
                    Text(date, format: Calendar.current.isDateInToday(date)
                         ? .dateTime.hour().minute() : .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if isCurrent {
                Text(localized("history.now"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            } else {
                Button { vm.restore(text) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .disabled(!canWrite)
                    .help(localized("history.restore"))
                    .accessibilityLabel(localized("history.restore"))
                if let onRemove = item.onRemove {
                    Button(action: onRemove) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(localized("history.remove"))
                        .accessibilityLabel(localized("history.remove"))
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // Double-click = restore, like double-clicking a step in Photoshop's History panel
        .onTapGesture(count: 2) { if canWrite { vm.restore(text) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityAction(named: localized("history.restore")) { if canWrite { vm.restore(text) } }
        .accessibilityAction(named: localized("history.remove")) { item.onRemove?() }
    }

    private func restoreButton(_ text: String) -> some View {
        Button(localized("history.restore")) { vm.restore(text) }
            .disabled(!canWrite || text == vm.rawText)
    }

    private func pin(_ text: String) {
        vm.history.pin(text, name: localized("history.pinDefault",
                                             Date.now.formatted(.dateTime.hour().minute())))
    }

    // swiftlint:disable cyclomatic_complexity
    /// Row title for a step: what changed to reach it. One case per change — a lookup table, not branching logic.
    static func title(_ change: HistoryChange) -> String {
        switch change {
        case .earliest: localized("history.earliest")
        case .opened: localized("history.opened")
        case .turnedOn(let name): localized("history.turnedOn", name)
        case .turnedOff(let name): localized("history.turnedOff", name)
        case .added(let name): localized("history.added", name)
        case .removed(let name): localized("history.removed", name)
        case .edited(let name): localized("history.edited", name)
        case .sectionAdded(let title):
            localized(title.isEmpty ? "history.sectionAddedUntitled" : "history.sectionAdded", title)
        case .sectionRemoved(let title):
            localized(title.isEmpty ? "history.sectionRemovedUntitled" : "history.sectionRemoved", title)
        case .sectionRenamed(let title): localized("history.sectionRenamed", title)
        case .moved: localized("history.moved")
        case .comments: localized("history.comments")
        case .reverted(let date):
            date.map { localized("history.reverted", $0.formatted(.dateTime.hour().minute())) }
                ?? localized("history.revertedEarlier")
        case .revertedToPin(let name): localized("history.revertedToPin", name)
        case .revertedToOpened: localized("history.revertedToOpened")
        case .several(let first, let more): localized("history.several", title(first), more)
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
