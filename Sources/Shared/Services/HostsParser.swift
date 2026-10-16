import CryptoKit
import Foundation

/// A parsed hosts file plus the formatting needed to write it back unchanged.
public struct HostsFile: Equatable, Sendable {
    public var lines: [HostsLine]
    public var lineEnding: String
    public var endsWithNewline: Bool

    public init(lines: [HostsLine] = [], lineEnding: String = "\n", endsWithNewline: Bool = true) {
        self.lines = lines
        self.lineEnding = lineEnding
        self.endsWithNewline = endsWithNewline
    }

    /// The file text. For a file read with `HostsParser.parse` and not modified, this equals the original.
    public var text: String {
        lines.map(\.text).joined(separator: lineEnding) + (endsWithNewline && !lines.isEmpty ? lineEnding : "")
    }
}

/// `/etc/hosts` ⇄ `[HostsLine]`. Never fails: anything it doesn't understand becomes `.unknown` and is kept verbatim.
public enum HostsParser {
    public static func parse(_ text: String) -> HostsFile {
        let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        var rawLines = text.components(separatedBy: lineEnding)
        let endsWithNewline = text.hasSuffix(lineEnding)
        if endsWithNewline { rawLines.removeLast() }
        if text.isEmpty { rawLines = [] }
        return HostsFile(lines: rawLines.map(parseLine), lineEnding: lineEnding, endsWithNewline: endsWithNewline)
    }

    static func parseLine(_ raw: String) -> HostsLine {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // ponytail: whitespace-only lines come back as empty lines when the file is written
        if trimmed.isEmpty { return .blank }

        if trimmed.hasPrefix("#") {
            // "# 127.0.0.1 a.test" is a disabled entry, anything else a comment
            let body = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            if let entry = parseEntry(body, isEnabled: false, raw: raw) { return .entry(entry) }
            return raw.hasPrefix("#") ? .comment(String(raw.dropFirst())) : .unknown(raw)
        }
        return parseEntry(trimmed, isEnabled: true, raw: raw).map(HostsLine.entry) ?? .unknown(raw)
    }

    static func parseEntry(_ body: String, isEnabled: Bool, raw: String) -> HostEntry? {
        var fields = Substring(body)
        var comment: String?
        if let hash = body.firstIndex(of: "#") {
            fields = body[..<hash]
            let text = body[body.index(after: hash)...].trimmingCharacters(in: .whitespaces)
            comment = text.isEmpty ? nil : text
        }
        let tokens = fields.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2, Validation.isIP(tokens[0]),
              tokens.dropFirst().allSatisfy(Validation.isHostname) else { return nil }
        return HostEntry(
            ip: tokens[0], hostnames: Array(tokens.dropFirst()), comment: comment, isEnabled: isEnabled, raw: raw
        )
    }
}

public enum Validation {
    /// IPv4 or IPv6 via `inet_pton`; IPv6 may carry a zone id (`fe80::1%lo0`).
    public static func isIP(_ text: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        if let percent = text.firstIndex(of: "%") {
            return percent != text.startIndex && inet_pton(AF_INET6, String(text[..<percent]), &v6) == 1
        }
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }

    // ponytail: strict RFC 1123 — names with "_" are rejected (kept verbatim as unknown lines when read from disk)
    /// RFC 1123: ≤ 253 chars, dot-separated labels of 1–63 letters/digits/hyphens, no leading/trailing hyphen.
    public static func isHostname(_ text: String) -> Bool {
        guard (1...253).contains(text.count) else { return false }
        return text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.count) && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

public extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
