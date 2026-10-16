import XCTest
@testable import Shared

final class HostsParserTests: XCTestCase {
    private static let stockMacOS = """
    ##
    # Host Database
    #
    # localhost is used to configure the loopback interface
    # when the system is booting.  Do not change this entry.
    ##
    127.0.0.1\tlocalhost
    255.255.255.255\tbroadcasthost
    ::1             localhost

    """

    // MARK: - Lossless round-trip (NFR-02)

    func testUntouchedFilesRoundTripByteForByte() {
        let fixtures = [
            Self.stockMacOS,
            "127.0.0.1 a.test\r\n# comment\r\n\r\n",                         // CRLF
            "127.0.0.1\t\ta.test   b.test\t# spaced  comment\n",            // tabs + multiple spaces
            "#127.0.0.1 off.test\n#  10.0.0.1 off2.test # why\n",            // disabled entries
            "fe80::1%lo0 localhost\n2001:db8::1 v6.test\n",                  // IPv6 + zone id
            "garbage line here\n  # indented comment\n1.2.3 not.ip\n",      // unknown lines
            "127.0.0.1 a.test",                                              // no trailing newline
            "",
            "\n\n"
        ]
        for text in fixtures {
            XCTAssertEqual(HostsParser.parse(text).text, text, text.debugDescription)
        }
    }

    // MARK: - Classification

    func testStockFileClassification() {
        let lines = HostsParser.parse(Self.stockMacOS).lines
        XCTAssertEqual(lines.count, 9)
        XCTAssertEqual(lines.first, .comment("#"))
        guard case .entry(let localhost) = lines[6], case .entry(let ipv6) = lines[8] else {
            return XCTFail("expected entries at 6 and 8")
        }
        XCTAssertTrue(localhost.isSystem)
        XCTAssertEqual(ipv6.ip, "::1")
    }

    func testDisabledEntryAndInlineComment() {
        guard case .entry(let entry) = HostsParser.parseLine("#  10.0.0.5 staging.test api.test  # VPN only") else {
            return XCTFail("expected a disabled entry")
        }
        XCTAssertFalse(entry.isEnabled)
        XCTAssertEqual(entry.hostnames, ["staging.test", "api.test"])
        XCTAssertEqual(entry.comment, "VPN only")
    }

    func testCommentThatIsNotAnEntryStaysAComment() {
        let comment = "# localhost is used to configure"
        XCTAssertEqual(HostsParser.parseLine(comment), .comment(" localhost is used to configure"))
        XCTAssertEqual(HostsParser.parseLine("  # indented"), .unknown("  # indented"))
        XCTAssertEqual(HostsParser.parseLine("   "), .blank)
    }

    func testInvalidEntriesAreKeptAsUnknown() {
        for raw in ["300.1.1.1 a.test", "127.0.0.1", "127.0.0.1 bad_name", "127.0.0.1 -dash.test"] {
            XCTAssertEqual(HostsParser.parseLine(raw), .unknown(raw), raw)
        }
    }

    // MARK: - Editing reformats only what changed

    func testChangedEntryIsRewrittenUnchangedEntriesKeepSpacing() {
        var file = HostsParser.parse("127.0.0.1   a.test\n10.0.0.1\t\tb.test\n")
        guard case .entry(var second) = file.lines[1] else { return XCTFail("expected entry") }
        second.isEnabled = false
        file.lines[1] = .entry(second)
        XCTAssertEqual(file.text, "127.0.0.1   a.test\n# 10.0.0.1\tb.test\n")
    }

    func testRevertingAChangeRestoresTheOriginalText() {
        guard case .entry(var entry) = HostsParser.parseLine("10.0.0.1\t\tb.test") else { return XCTFail("entry") }
        entry.isEnabled = false
        entry.isEnabled = true
        XCTAssertEqual(entry.line, "10.0.0.1\t\tb.test")
    }

    // MARK: - Validation

    func testIPValidation() {
        for valid in ["127.0.0.1", "0.0.0.0", "255.255.255.255", "::1", "2001:db8::1", "fe80::1%lo0"] {
            XCTAssertTrue(Validation.isIP(valid), valid)
        }
        for invalid in ["256.0.0.1", "1.2.3", "1.2.3.4.5", "abc", "", "%lo0", "127.0.0.1%lo0", "::1::2"] {
            XCTAssertFalse(Validation.isIP(invalid), invalid)
        }
    }

    func testHostnameValidation() {
        for valid in ["localhost", "api.test", "a-b.example.com", "x", String(repeating: "a", count: 63) + ".test"] {
            XCTAssertTrue(Validation.isHostname(valid), valid)
        }
        let invalid = ["", "-a.test", "a-.test", "a..test", "a_b.test", "ü.test", String(repeating: "a", count: 64)]
        for name in invalid {
            XCTAssertFalse(Validation.isHostname(name), name)
        }
    }

    func testSHA256Hex() {
        XCTAssertEqual(Data("abc".utf8).sha256Hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
