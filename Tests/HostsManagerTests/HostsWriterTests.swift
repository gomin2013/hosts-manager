import XCTest
import Shared
@testable import HostsManagerHelper

/// The root write pipeline against a temp directory — never the real /etc/hosts.
final class HostsWriterTests: XCTestCase {
    private var root: URL!
    private var writer: HostsWriter!
    private let flushes = Counter()

    private let original = "##\n# Host Database\n##\n127.0.0.1\tlocalhost\n"
    private let updated = "127.0.0.1\tlocalhost\n127.0.0.1\tapi.test\n"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("HostsWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try original.write(to: root.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        let flushes = flushes
        writer = HostsWriter(
            hostsURL: root.appendingPathComponent("hosts"),
            backupsURL: root.appendingPathComponent("Backups", isDirectory: true),
            keepBackups: 3,
            flushDNS: { flushes.increment() }
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var hostsText: String { (try? String(contentsOf: writer.hostsURL, encoding: .utf8)) ?? "" }
    private var hostsHash: String { (try? Data(contentsOf: writer.hostsURL))?.sha256Hex ?? "" }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: writer.backupsURL.path).sorted()
    }

    func testWriteBacksUpWrites0644AndFlushes() throws {
        try writer.write(updated, expectedSHA256: hostsHash)

        XCTAssertEqual(hostsText, updated)
        let attributes = try FileManager.default.attributesOfItem(atPath: writer.hostsURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o644)
        let backup = try XCTUnwrap(backups().first)
        XCTAssertEqual(
            try String(contentsOf: writer.backupsURL.appendingPathComponent(backup), encoding: .utf8), original
        )
        XCTAssertEqual(flushes.value, 1)
    }

    func testStaleHashIsRejectedAndNothingChanges() {
        XCTAssertThrowsError(try writer.write(updated, expectedSHA256: Data("other".utf8).sha256Hex)) {
            XCTAssertEqual($0 as? HelperError, .staleFile)
        }
        XCTAssertEqual(hostsText, original)
        XCTAssertEqual(flushes.value, 0)
    }

    func testInvalidContentIsRejected() {
        let tooBig = "127.0.0.1 localhost\n" + String(repeating: "#", count: HostsWriter.maxBytes)
        for bad in ["127.0.0.1 localhost\n\0", "127.0.0.1 api.test\n", "# 127.0.0.1 localhost\n", tooBig] {
            XCTAssertThrowsError(try writer.write(bad, expectedSHA256: hostsHash)) {
                XCTAssertEqual($0 as? HelperError, .invalidContent)
            }
        }
        XCTAssertEqual(hostsText, original)
    }

    func testOnlyTheNewestBackupsAreKept() throws {
        for index in 0..<5 {
            try writer.write("127.0.0.1 localhost\n# v\(index)\n", expectedSHA256: hostsHash)
        }
        XCTAssertEqual(try backups().count, 3)
        let newest = try XCTUnwrap(backups().last)
        XCTAssertEqual(
            try String(contentsOf: writer.backupsURL.appendingPathComponent(newest), encoding: .utf8),
            "127.0.0.1 localhost\n# v3\n"
        )
    }

    func testMissingHostsFileHashesAsEmpty() throws {
        try FileManager.default.removeItem(at: writer.hostsURL)
        try writer.write(updated, expectedSHA256: Data().sha256Hex)
        XCTAssertEqual(hostsText, updated)
    }
}

/// Thread-safe counter for the injected DNS flush.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
