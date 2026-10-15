import Foundation

/// Errors crossing the XPC boundary. The app shows `"err.<case>"` from Localizable.strings.
public enum HelperError: String, Error, Codable, CaseIterable, Sendable {
    case notInstalled
    case connectionFailed
    /// `/etc/hosts` changed on disk since the app loaded it.
    case staleFile
    /// Rejected by the helper's own validation (size, encoding, NUL bytes).
    case invalidContent
    case writeFailed

    public var localizationKey: String { "err.\(rawValue)" }

    public static let domain = "com.hostsmanager.helper"

    public var nsError: NSError {
        NSError(domain: Self.domain, code: Self.allCases.firstIndex(of: self) ?? -1)
    }

    public init?(_ error: NSError) {
        guard error.domain == Self.domain, Self.allCases.indices.contains(error.code) else { return nil }
        self = Self.allCases[error.code]
    }
}
