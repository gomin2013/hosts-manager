import XCTest
@testable import Shared

final class ModelTests: XCTestCase {

    // MARK: - HostEntry.isSystem

    func testStockMacOSEntriesAreSystem() {
        XCTAssertTrue(HostEntry(ip: "127.0.0.1", hostnames: ["localhost"]).isSystem)
        XCTAssertTrue(HostEntry(ip: "255.255.255.255", hostnames: ["broadcasthost"]).isSystem)
        XCTAssertTrue(HostEntry(ip: "::1", hostnames: ["localhost"]).isSystem)
        XCTAssertTrue(HostEntry(ip: "fe80::1%lo0", hostnames: ["localhost"]).isSystem)
    }

    func testUserEntriesAreNotSystem() {
        XCTAssertFalse(HostEntry(ip: "127.0.0.1", hostnames: ["api.test"]).isSystem)
        XCTAssertFalse(HostEntry(ip: "10.0.0.1", hostnames: ["localhost"]).isSystem)
        XCTAssertFalse(HostEntry(ip: "0.0.0.0", hostnames: ["broadcasthost"]).isSystem)
    }

    // MARK: - HostEntry.lines

    func testEnabledLine() {
        let entry = HostEntry(ip: "127.0.0.1", hostnames: ["api.test", "web.test"])
        XCTAssertEqual(entry.lines, ["127.0.0.1\tapi.test web.test"])
    }

    func testDisabledLineWithCommentIsCommentedOut() {
        let entry = HostEntry(ip: "10.0.0.5", hostnames: ["staging.test"], comment: "VPN", isEnabled: false)
        XCTAssertEqual(entry.lines, ["## VPN", "# 10.0.0.5\tstaging.test"])
    }

    func testCommentCannotInjectAHostsLine() {
        let entry = HostEntry(ip: "127.0.0.1", hostnames: ["a.test"], comment: "dev\n10.6.6.6 bank.example\r\u{0}# x")
        XCTAssertEqual(entry.lines, ["## dev 10.6.6.6 bank.example   x", "127.0.0.1\ta.test"])
        let parsed = HostsParser.parse(entry.lines.joined(separator: "\n") + "\n").lines
        XCTAssertEqual(parsed.count, 1, "one entry, its comment on the line above")
        guard case .entry(let back) = parsed.first else { return XCTFail("not an entry") }
        XCTAssertEqual(back.hostnames, ["a.test"], "bank.example never becomes a name for 127.0.0.1")
    }

    func testEmptyCommentIsOmitted() {
        XCTAssertEqual(HostEntry(ip: "::1", hostnames: ["a.test"], comment: "").lines, ["::1\ta.test"])
    }

    // MARK: - HostEntry.matches

    func testMatchesIPOrAnyHostnameCaseInsensitively() {
        let entry = HostEntry(ip: "10.0.0.5", hostnames: ["Staging.Example.com", "api.test"])
        XCTAssertTrue(entry.matches("10.0"))
        XCTAssertTrue(entry.matches("staging"))
        XCTAssertTrue(entry.matches("API"))
        XCTAssertTrue(entry.matches("  "))
        XCTAssertFalse(entry.matches("prod"))
    }

    func testCommentIsNotSearched() {
        XCTAssertFalse(HostEntry(ip: "1.1.1.1", hostnames: ["a.test"], comment: "docker").matches("docker"))
    }

    // MARK: - Codable (crosses XPC in later phases)

    func testHostsLineCodableRoundTrip() throws {
        let lines: [HostsLine] = [
            .comment("Local dev"),
            .entry(HostEntry(ip: "127.0.0.1", hostnames: ["a.test"], comment: "x", isEnabled: false)),
            .blank,
            .unknown("garbage line")
        ]
        let decoded = try JSONDecoder().decode([HostsLine].self, from: JSONEncoder().encode(lines))
        XCTAssertEqual(decoded, lines)
    }

    // MARK: - HostsLine.text / serialize

    func testLineTextRoundTripsEachKind() {
        XCTAssertEqual(HostsLine.comment(" Local dev").text, "# Local dev")
        XCTAssertEqual(HostsLine.comment("#").text, "##")
        XCTAssertEqual(HostsLine.blank.text, "")
        XCTAssertEqual(HostsLine.unknown("garbage  line").text, "garbage  line")
    }

    func testSerializeEndsWithNewline() {
        XCTAssertEqual(HostsLine.serialize([.comment(" a"), .blank]), "# a\n\n")
    }

    // MARK: - HelperError

    func testHelperErrorNSErrorRoundTrip() {
        for error in HelperError.allCases {
            XCTAssertEqual(HelperError(error.nsError), error)
        }
        XCTAssertNil(HelperError(NSError(domain: "other", code: 0)))
        XCTAssertNil(HelperError(NSError(domain: HelperError.domain, code: 99)))
    }
}
