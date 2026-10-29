import XCTest
@testable import HostsManagerApp

/// The two pure parts of Check for Updates: which version is newer, and reading GitHub's `releases/latest`.
final class UpdateCheckerTests: XCTestCase {
    func testNewerIsNumericNotAlphabetical() {
        XCTAssertTrue(UpdateChecker.isNewer("1.1.10", than: "1.1.9"))    // as strings this would be older
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.10.3"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1.3", than: "1.1.3"))    // same = up to date
        XCTAssertFalse(UpdateChecker.isNewer("1.1.2", than: "1.1.3"))    // running a newer local build
    }

    /// Trimmed copy of a real response: only the fields the app reads, plus one it ignores.
    func testDecodesTheLatestRelease() throws {
        let json = """
        {"tag_name": "v1.1.4", "html_url": "https://github.com/gomin2013/hosts-manager/releases/tag/v1.1.4",
         "body": "## v1.1.4\\n\\n- **Check for Updates**", "draft": false,
         "assets": [{"name": "SHA256SUMS.txt", "browser_download_url": "https://example.com/SHA256SUMS.txt"},
                    {"name": "App-1.1.4.dmg", "browser_download_url": "https://example.com/a.dmg"}]}
        """
        let release = try UpdateChecker.decode(Data(json.utf8))
        XCTAssertEqual(release.version, "1.1.4")                          // "v" stripped
        XCTAssertEqual(release.download.absoluteString, "https://example.com/a.dmg")   // the DMG, not the checksum
        XCTAssertEqual(release.notes, "## v1.1.4\n\n- **Check for Updates**")
    }

    func testNotesDropTheVersionHeadingAndMarkdown() {
        let notes = "## v1.1.4 — 2026-10-29\n\n### Added\n\n- **Check for Updates** in the app menu"
        XCTAssertEqual(UpdateChecker.plainNotes(notes), "Added\n\n- Check for Updates in the app menu")
    }

    func testNoDMGFallsBackToTheReleasePage() throws {
        let json = #"{"tag_name": "v1.1.4", "html_url": "https://example.com/page", "body": null, "assets": []}"#
        let release = try UpdateChecker.decode(Data(json.utf8))
        XCTAssertEqual(release.download.absoluteString, "https://example.com/page")
        XCTAssertNil(release.notes)
    }
}
