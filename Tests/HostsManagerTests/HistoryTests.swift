import XCTest
import Shared
@testable import HostsManagerApp

/// History panel: step titles from diffs, ordering and dates from the helper's backups, reverts, pins.
@MainActor
final class HistoryTests: XCTestCase {
    private let base = "127.0.0.1\tlocalhost\n\n# Dev\n127.0.0.1\tapi.test\n# 127.0.0.1\tadmin.test\n"

    private func change(_ old: String, _ new: String) -> HistoryChange { HistoryDiff.change(from: old, to: new) }

    // MARK: - Titles

    func testToggleAddDeleteAndEdit() {
        XCTAssertEqual(change(base, base.replacingOccurrences(of: "# 127.0.0.1\tadmin", with: "127.0.0.1\tadmin")),
                       .turnedOn("admin.test"))
        XCTAssertEqual(change(base, base.replacingOccurrences(of: "127.0.0.1\tapi", with: "# 127.0.0.1\tapi")),
                       .turnedOff("api.test"))
        XCTAssertEqual(change(base, base + "0.0.0.0\tads.test\n"), .added("ads.test"))
        XCTAssertEqual(change(base, base.replacingOccurrences(of: "127.0.0.1\tapi.test\n", with: "")),
                       .removed("api.test"))
        XCTAssertEqual(change(base, base.replacingOccurrences(of: "127.0.0.1\tapi.test", with: "10.0.0.1\tapi.test")),
                       .edited("api.test"))
        XCTAssertEqual(change(base, base.replacingOccurrences(of: "api.test", with: "api.test\t# docker")),
                       .edited("api.test"))
    }

    func testSections() {
        XCTAssertEqual(change(base, base + "\n# Staging\n"), .sectionAdded("Staging"))
        XCTAssertEqual(change(base, base + "\n"), .sectionAdded(""))
        XCTAssertEqual(change(base, base.replacingOccurrences(of: "# Dev", with: "# Local dev")),
                       .sectionRenamed("Local dev"))
    }

    func testMovedAndSeveral() {
        let swapped = "127.0.0.1\tlocalhost\n\n# Dev\n# 127.0.0.1\tadmin.test\n127.0.0.1\tapi.test\n"
        XCTAssertEqual(change(base, swapped), .moved)
        XCTAssertEqual(change(base, base + "0.0.0.0\ta.test\n0.0.0.0\tb.test\n"), .several(.added("a.test"), more: 1))
    }

    // MARK: - States

    func testStatesAreNewestFirstAndDatedByTheNextBackup() {
        let first = Date(timeIntervalSince1970: 100), second = Date(timeIntervalSince1970: 200)
        let v2 = base + "0.0.0.0\tads.test\n"
        let states = HostsHistory.states(
            previous: [.init(id: "b1", replacedAt: first, text: base), .init(id: "b2", replacedAt: second, text: v2)],
            current: base
        )
        XCTAssertEqual(states.map(\.id), ["current", "b2", "b1"])
        XCTAssertEqual(states.map(\.date), [second, first, nil])
        XCTAssertEqual(states[1].change, .added("ads.test"))
        XCTAssertEqual(states[0].change, .reverted(to: nil), "current equals b1, two steps back")
        XCTAssertEqual(states[2].change, .earliest)
    }

    func testRevertToAPinIsNamedAfterThePin() {
        let pin = PinnedSnapshot(name: "Before VPN", date: .distantPast, text: base)
        let states = HostsHistory.states(
            previous: [.init(id: "b1", replacedAt: .now, text: base + "\n")], current: base, pins: [pin]
        )
        XCTAssertEqual(states[0].change, .revertedToPin("Before VPN"))
    }

    // MARK: - Disk

    func testReadsHelperBackupsAndKeepsTheNewestShownCount() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(HostsHistory.shownCount, 30)
        XCTAssertEqual(HostsHistory.shownCount, HelperConstants.keptBackups, "shows every backup the helper keeps")
        for index in 0..<(HostsHistory.shownCount + 2) {
            let stamp = String(format: "2026-10-19T10:%02d:00.000Z", index)
            try Data((base + "# \(index)\n").utf8).write(to: dir.appendingPathComponent("hosts-\(stamp)"))
        }
        let history = HostsHistory(backupsURL: dir, pinsURL: nil)
        history.reload(current: base)
        XCTAssertEqual(history.recent.count, HostsHistory.shownCount + 1, "shownCount backups + the current file")
        XCTAssertEqual(history.recent.last?.id, "hosts-2026-10-19T10:02:00.000Z")
    }

    func testRemovedStepsStayHiddenAcrossLaunchesAndNowCannotBeRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for index in 0..<3 {
            let stamp = String(format: "2026-10-19T11:%02d:00.000Z", index)
            try Data((base + "# \(index)\n").utf8).write(to: dir.appendingPathComponent("hosts-\(stamp)"))
        }
        let hiddenURL = dir.appendingPathComponent("history-hidden.json")
        let history = HostsHistory(backupsURL: dir, pinsURL: nil, hiddenURL: hiddenURL)
        history.reload(current: base)
        let middle = "hosts-2026-10-19T11:01:00.000Z"
        history.remove(middle)
        history.remove("current")
        XCTAssertFalse(history.recent.contains { $0.id == middle })
        XCTAssertTrue(history.recent.contains { $0.id == "current" }, "Now stays")

        let reopened = HostsHistory(backupsURL: dir, pinsURL: nil, hiddenURL: hiddenURL)
        reopened.reload(current: base)
        XCTAssertEqual(reopened.recent.map(\.id), ["current", "hosts-2026-10-19T11:02:00.000Z",
                                                  "hosts-2026-10-19T11:00:00.000Z"])

        // Once the helper prunes that backup, its removal is forgotten
        try FileManager.default.removeItem(at: dir.appendingPathComponent(middle))
        reopened.reload(current: base)
        XCTAssertTrue(reopened.hidden.isEmpty)
    }

    func testPinsPersistAcrossLaunches() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pins-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let history = HostsHistory(backupsURL: nil, pinsURL: url)
        history.pin(base, name: "Before VPN")
        history.rename(try XCTUnwrap(history.pins.first).id, to: "Clean")

        let reopened = HostsHistory(backupsURL: nil, pinsURL: url)
        XCTAssertEqual(reopened.pins.map(\.name), ["Clean"])
        reopened.unpin(try XCTUnwrap(reopened.pins.first).id)
        XCTAssertTrue(HostsHistory(backupsURL: nil, pinsURL: url).pins.isEmpty)
    }

    func testAStateIsNotARestoreOfAPinMadeFromIt() {
        let pin = PinnedSnapshot(name: "Before VPN", date: .distantFuture, text: base)
        let states = HostsHistory.states(
            previous: [.init(id: "b1", replacedAt: .now, text: base + "\n")], current: base, pins: [pin]
        )
        XCTAssertEqual(states[0].change, .sectionRemoved(""), "pinned after this step — not a restore of it")
    }

    func testEveryChangeHasATitle() {
        let changes: [HistoryChange] = [
            .earliest, .opened, .turnedOn("a"), .turnedOff("a"), .added("a"), .removed("a"), .edited("a"),
            .sectionAdded(""),
            .sectionAdded("S"), .sectionRemoved(""), .sectionRemoved("S"), .sectionRenamed("S"), .moved, .comments,
            .reverted(to: nil), .reverted(to: .now), .revertedToPin("P"), .revertedToOpened, .several(.moved, more: 2)
        ]
        for change in changes {
            let title = HistoryPanel.title(change)
            XCTAssertFalse(title.isEmpty || title.hasPrefix("history."), "\(change) → \(title)")
        }
    }
}
