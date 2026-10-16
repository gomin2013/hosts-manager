import Foundation
import os
import Shared

/// The only code that writes `/etc/hosts`. Runs as root inside the helper.
/// validate → stale check → backup → atomic write → 0644 → DNS flush. Paths are injectable for tests only.
struct HostsWriter: Sendable {
    var hostsURL = URL(fileURLWithPath: "/private/etc/hosts")
    /// Root-owned, never world-writable (constraints.md: no /tmp, no /var/tmp).
    var backupsURL = URL(fileURLWithPath: HelperConstants.backupsPath, isDirectory: true)
    var keepBackups = 20
    var flushDNS: @Sendable () -> Void = HostsWriter.flushDNSCache

    static let maxBytes = 1_048_576
    private static let logger = Logger(subsystem: "com.hostsmanager", category: "helper")

    func write(_ content: String, expectedSHA256: String) throws(HelperError) {
        try Self.validate(content)

        let current = (try? Data(contentsOf: hostsURL)) ?? Data()
        guard current.sha256Hex == expectedSHA256 else { throw .staleFile }

        do {
            try backUp(current)
            try Data(content.utf8).write(to: hostsURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: hostsURL.path)
        } catch {
            Self.logger.error("write failed: \(error.localizedDescription, privacy: .public)")
            throw .writeFailed
        }
        flushDNS()
    }

    /// Never trust the client: size, encoding, NUL bytes, and the file must keep an enabled `127.0.0.1 localhost`.
    static func validate(_ content: String) throws(HelperError) {
        guard content.utf8.count <= maxBytes, !content.contains("\0") else { throw .invalidContent }
        let keepsLocalhost = HostsParser.parse(content).lines.contains { line in
            guard case .entry(let entry) = line else { return false }
            return entry.isEnabled && entry.ip == "127.0.0.1" && entry.hostnames.contains("localhost")
        }
        guard keepsLocalhost else { throw .invalidContent }
    }

    /// `Backups/hosts-<timestamp>`, 0644 so the app can read them for Restore Previous; keeps the newest `keepBackups`.
    private func backUp(_ data: Data) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: backupsURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755]
        )
        let stamp = ISO8601DateFormatter.string(
            from: Date(), timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        )
        let backup = backupsURL.appendingPathComponent("hosts-\(stamp)")
        try data.write(to: backup, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: backup.path)

        let backups = try fileManager.contentsOfDirectory(atPath: backupsURL.path)
            .filter { $0.hasPrefix("hosts-") }
            .sorted()
        for old in backups.dropLast(keepBackups) {
            try? fileManager.removeItem(at: backupsURL.appendingPathComponent(old))
        }
    }

    /// Fixed argv, no shell.
    static func flushDNSCache() {
        let commands = [("/usr/bin/dscacheutil", ["-flushcache"]), ("/usr/bin/killall", ["-HUP", "mDNSResponder"])]
        for (tool, args) in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = args
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                logger.error("\(tool, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
