import Foundation

/// One `<ip> <hostname>…` line of `/etc/hosts`. A disabled entry is written commented out (`# 127.0.0.1 a.test`).
public struct HostEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var ip: String
    public var hostnames: [String]
    /// Inline comment after the hostnames, without the leading `#`.
    public var comment: String?
    public var isEnabled: Bool
    /// The line as read from disk and the fields it parsed to. While the fields are unchanged, `line` returns the
    /// original text (tabs, spacing) so an untouched entry is written back byte-for-byte.
    private var source: Source?

    private struct Source: Codable, Hashable, Sendable {
        let raw: String
        let ip: String
        let hostnames: [String]
        let comment: String?
        let isEnabled: Bool
    }

    public init(
        id: UUID = UUID(),
        ip: String,
        hostnames: [String],
        comment: String? = nil,
        isEnabled: Bool = true,
        raw: String? = nil
    ) {
        self.id = id
        self.ip = ip
        self.hostnames = hostnames
        self.comment = comment
        self.isEnabled = isEnabled
        self.source = raw.map { Source(raw: $0, ip: ip, hostnames: hostnames, comment: comment, isEnabled: isEnabled) }
    }

    // ponytail: an entry that adds extra names to `127.0.0.1 localhost` is still locked; split it if users complain
    /// Entries macOS ships with. They are read-only: no edit, toggle, delete or drag.
    static let systemPairs: [(ip: String, hostname: String)] = [
        ("127.0.0.1", "localhost"),
        ("255.255.255.255", "broadcasthost"),
        ("::1", "localhost"),
        ("fe80::1%lo0", "localhost")
    ]

    public var isSystem: Bool {
        Self.systemPairs.contains { ip == $0.ip && hostnames.contains($0.hostname) }
    }

    /// The line as written to `/etc/hosts`.
    public var line: String {
        if let source, source.ip == ip, source.hostnames == hostnames,
           source.comment == comment, source.isEnabled == isEnabled {
            return source.raw
        }
        var text = "\(ip)\t\(hostnames.joined(separator: " "))"
        if let comment = comment.map(Self.oneLine), !comment.isEmpty { text += "\t# \(comment)" }
        return isEnabled ? text : "# \(text)"
    }

    /// A comment can never add a line to /etc/hosts: newlines / control characters become spaces, `#` is dropped.
    /// (IP and hostnames can't carry them — `Validation` rejects anything but letters, digits, `.`, `-`, `:`, `%`.)
    public static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "#", with: "")
            .components(separatedBy: CharacterSet.newlines.union(.controlCharacters))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Case-insensitive match against the IP or any hostname. Empty query matches everything.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ip.localizedCaseInsensitiveContains(query)
            || hostnames.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
