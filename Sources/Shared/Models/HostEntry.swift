import Foundation

/// One `<ip> <hostname>…` line of `/etc/hosts`. A disabled entry is written commented out (`# 127.0.0.1 a.test`).
/// Its comment goes on its own `## text` line above: macOS reads `127.0.0.1 a.test # local` as three names —
/// `a.test`, `#` and `local` all resolve to 127.0.0.1 (seen 2026-10-21, despite `man 5 hosts`).
public struct HostEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var ip: String
    public var hostnames: [String]
    /// The `## text` line above the entry, without the `## `.
    public var comment: String?
    public var isEnabled: Bool
    /// The line(s) as read from disk and the fields they parsed to. While the fields are unchanged, `lines` returns
    /// the original text (tabs, spacing) so an untouched entry is written back byte-for-byte.
    private var source: Source?

    private struct Source: Codable, Hashable, Sendable {
        let raw: String
        var commentLine: String?
        let ip: String
        let hostnames: [String]
        var comment: String?
        let isEnabled: Bool
        /// Read as `ip host # comment` (v1.0, or written by hand): never written back as-is.
        let inlineComment: Bool
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
        // From the parser, a comment can only have come from the same line (the `##` line is attached afterwards).
        self.source = raw.map {
            Source(raw: $0, ip: ip, hostnames: hostnames, comment: comment, isEnabled: isEnabled,
                   inlineComment: comment != nil)
        }
    }

    /// Parser: the `## text` line right above this entry is its comment.
    mutating func attachCommentLine(_ line: String, text: String) {
        comment = text
        source?.comment = text
        source?.commentLine = line
    }

    /// Enabled and still has a same-line comment on disk, so macOS also resolves the comment's words. The next save
    /// moves the comment to its own line.
    public var hasInlineComment: Bool { isEnabled && source?.inlineComment == true }

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

    /// The line(s) as written to `/etc/hosts`: an optional `## comment` line, then the entry.
    public var lines: [String] {
        var entryLine = "\(ip)\t\(hostnames.joined(separator: " "))"
        if !isEnabled { entryLine = "# " + entryLine }
        if let source, !source.inlineComment, source.ip == ip, source.hostnames == hostnames,
           source.isEnabled == isEnabled {
            entryLine = source.raw
        }
        guard let text = comment.map(Self.oneLine), !text.isEmpty else { return [entryLine] }
        let commentLine = source?.comment == comment ? source?.commentLine : nil
        return [commentLine ?? "## " + text, entryLine]
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
