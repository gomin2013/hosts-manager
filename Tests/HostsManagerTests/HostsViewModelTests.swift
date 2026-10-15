import XCTest
import Shared
@testable import HostsManagerApp

@MainActor
final class HostsViewModelTests: XCTestCase {

    private func entry(_ ip: String, _ hosts: String...) -> HostsLine {
        .entry(HostEntry(ip: ip, hostnames: hosts))
    }

    // MARK: - Rows (git-exclude-manager convention)

    func testStockMacOSHeaderIsOneSystemCommentBlock() {
        let lines: [HostsLine] = [
            .comment("#"), .comment(" Host Database"), .comment("#"), entry("127.0.0.1", "localhost")
        ]
        let rows = HostsViewModel.rows(from: lines)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first, .comment(id: 0, text: "##\n# Host Database\n##", isSystem: true))
    }

    func testCommentBlockAfterEntriesIsNotSystem() {
        let rows = HostsViewModel.rows(from: [entry("1.1.1.1", "a.test"), .comment(" Host Database")])
        XCTAssertEqual(rows.last, .comment(id: 1, text: "# Host Database", isSystem: false))
    }

    func testBlankPlusOneCommentIsAHeadedSection() {
        let rows = HostsViewModel.rows(from: [.blank, .comment(" Local dev"), entry("127.0.0.1", "a.test")])
        XCTAssertEqual(rows.first, .section(id: 0, title: "Local dev"))
        XCTAssertEqual(rows.count, 2)
    }

    func testBlankAloneIsAnUntitledSection() {
        let rows = HostsViewModel.rows(from: [entry("1.1.1.1", "a.test"), .blank, entry("2.2.2.2", "b.test")])
        XCTAssertEqual(rows.map(\.id), [0, 1, 2])
        XCTAssertEqual(rows[1], .section(id: 1, title: ""))
    }

    func testBlankBeforeACommentRunKeepsTheRunVerbatim() {
        let rows = HostsViewModel.rows(from: [.blank, .comment(" one"), .comment(" two")])
        XCTAssertEqual(rows, [.section(id: 0, title: ""), .comment(id: 1, text: "# one\n# two", isSystem: false)])
    }

    func testUnknownLinesJoinCommentBlocks() {
        let rows = HostsViewModel.rows(from: [.comment(" note"), .unknown("garbage")])
        XCTAssertEqual(rows, [.comment(id: 0, text: "# note\ngarbage", isSystem: false)])
    }

    func testMockDataRowShape() {
        let kinds = HostsViewModel.rows(from: MockData.lines).map { row -> String in
            switch row {
            case .section(_, let title): "§\(title)"
            case .comment(_, _, let isSystem): isSystem ? "header" : "comment"
            case .entry: "e"
            }
        }
        XCTAssertEqual(kinds, ["header", "e", "e", "e", "§Local dev", "e", "e", "§Staging", "e", "e", "§Blocked", "e"])
    }

    func testLargeFileIsFast() {
        let lines = [HostsLine.blank, .comment(" Blocked")] + (0..<10_000).map { entry("0.0.0.0", "h\($0).test") }
        measure { XCTAssertEqual(HostsViewModel.rows(from: lines).count, 10_001) }
    }

    // MARK: - Search

    func testSearchShowsOnlyMatchingEntries() {
        let vm = HostsViewModel()
        vm.searchText = "staging"
        let hosts = vm.filteredRows.compactMap { row -> String? in
            if case .entry(_, let found) = row { found.hostnames.first } else { nil }
        }
        XCTAssertEqual(hosts, ["staging.example.com", "staging6.example.com"])
        XCTAssertEqual(vm.filteredRows.count, 2, "sections and comments are hidden while searching")
    }

    func testEmptySearchShowsEverything() {
        let vm = HostsViewModel()
        XCTAssertEqual(vm.filteredRows, HostsViewModel.rows(from: vm.lines))
    }

    func testCounts() {
        let vm = HostsViewModel()
        XCTAssertEqual(vm.entries.count, 8)
        XCTAssertEqual(vm.enabledCount, 5)
    }

    func testRawTextIsTheSerializedFile() {
        let vm = HostsViewModel(lines: [.comment(" Dev"), entry("127.0.0.1", "a.test"), .blank])
        XCTAssertEqual(vm.rawText, "# Dev\n127.0.0.1\ta.test\n\n")
    }

    // MARK: - Editor

    func testBeginEditRefusesSystemEntries() {
        let vm = HostsViewModel()
        vm.beginEdit(HostEntry(ip: "127.0.0.1", hostnames: ["localhost"]))
        XCTAssertNil(vm.editor)
    }

    func testEditorPrefillsAndSplitsHostnames() {
        let vm = HostsViewModel()
        vm.beginEdit(HostEntry(ip: "127.0.0.1", hostnames: ["a.test", "b.test"], comment: "dev"))
        XCTAssertEqual(vm.editor?.ip, "127.0.0.1")
        XCTAssertEqual(vm.editor?.hostnamesText, "a.test b.test")
        XCTAssertEqual(vm.editor?.titleKey, "editor.editTitle")

        vm.editor?.hostnamesText = "  x.test\ty.test  "
        XCTAssertEqual(vm.editor?.hostnames, ["x.test", "y.test"])
    }

    func testBeginAddOpensEmptyEditor() {
        let vm = HostsViewModel()
        vm.beginAdd()
        XCTAssertEqual(vm.editor?.isEditing, false)
        XCTAssertEqual(vm.editor?.titleKey, "editor.addTitle")
    }
}
