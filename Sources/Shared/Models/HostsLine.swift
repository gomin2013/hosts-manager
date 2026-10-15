import Foundation

/// Every line of `/etc/hosts` is kept so an untouched file serializes back byte-for-byte (ADR-005).
public enum HostsLine: Codable, Hashable, Sendable {
    case entry(HostEntry)
    /// Text after the leading `#` (`"# Local dev"` → `" Local dev"`).
    case comment(String)
    case blank
    /// Not a valid entry or comment — preserved verbatim.
    case unknown(String)

    /// The line as written to the file.
    public var text: String {
        switch self {
        case .entry(let entry): entry.line
        case .comment(let text): "#" + text
        case .blank: ""
        case .unknown(let raw): raw
        }
    }

    // ponytail: no CRLF / trailing-newline preservation yet — the Phase 2 parser keeps the original line endings
    public static func serialize(_ lines: [HostsLine]) -> String {
        lines.map(\.text).joined(separator: "\n") + "\n"
    }
}
