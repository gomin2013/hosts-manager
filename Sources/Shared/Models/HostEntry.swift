import Foundation

/// One `<ip> <hostname>…` line of `/etc/hosts`. A disabled entry is written commented out (`# 127.0.0.1 a.test`).
public struct HostEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var ip: String
    public var hostnames: [String]
    /// Inline comment after the hostnames, without the leading `#`.
    public var comment: String?
    public var isEnabled: Bool

    public init(id: UUID = UUID(), ip: String, hostnames: [String], comment: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.ip = ip
        self.hostnames = hostnames
        self.comment = comment
        self.isEnabled = isEnabled
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
        var text = "\(ip)\t\(hostnames.joined(separator: " "))"
        if let comment, !comment.isEmpty { text += "\t# \(comment)" }
        return isEnabled ? text : "# \(text)"
    }

    /// Case-insensitive match against the IP or any hostname. Empty query matches everything.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ip.localizedCaseInsensitiveContains(query)
            || hostnames.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
