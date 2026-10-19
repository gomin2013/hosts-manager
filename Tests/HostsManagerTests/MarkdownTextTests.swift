import XCTest
@testable import HostsManagerApp

/// Block splitting for AI replies.
final class MarkdownTextTests: XCTestCase {
    func testTypicalReply() {
        let reply = """
        ## Add these lines
        Point **both** names at your machine:

        ```
        127.0.0.1 api.test
        127.0.0.1 web.test
        ```
        - first
          - nested
        2. second
        > note
        ---
        """
        XCTAssertEqual(MarkdownText.blocks(reply), [
            .heading(level: 2, text: "Add these lines"),
            .paragraph("Point **both** names at your machine:"),
            .code("127.0.0.1 api.test\n127.0.0.1 web.test"),
            .bullet(level: 0, text: "first"),
            .bullet(level: 1, text: "nested"),
            .numbered(marker: "2.", text: "second"),
            .quote("note"),
            .rule
        ])
    }

    func testUnclosedFenceWhileStreamingStillShowsTheCode() {
        XCTAssertEqual(MarkdownText.blocks("Try:\n```\n0.0.0.0 ads.test"), [
            .paragraph("Try:"), .code("0.0.0.0 ads.test")
        ])
    }

    func testTableSkipsTheSeparatorRow() {
        XCTAssertEqual(MarkdownText.blocks("| IP | Host |\n|---|:---|\n| 127.0.0.1 | a.test |"), [
            .table([["IP", "Host"], ["127.0.0.1", "a.test"]])
        ])
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(MarkdownText.blocks("#comment\n# Real"), [
            .paragraph("#comment"), .heading(level: 1, text: "Real")
        ])
    }
}
