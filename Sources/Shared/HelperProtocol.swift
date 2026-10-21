import Foundation

public enum HelperConstants {
    public static let machServiceName = "com.hostsmanager.helper"
    public static let appBundleIdentifier = "com.hostsmanager.app"
    public static let daemonPlistName = "com.hostsmanager.helper.plist"
    public static let hostsPath = "/etc/hosts"
    /// Root-owned; the helper writes `hosts-<ISO8601>` here before every change, the app reads them (0644).
    public static let backupsPath = "/Library/Application Support/HostsManager/Backups"
    /// Backups the helper keeps = steps the History panel can show. One number for both sides.
    public static let keptBackups = 30
}

/// XPC contract between the app and the root helper. The helper only *writes*; the app reads `/etc/hosts` itself.
/// Adding a method here requires an XPC integration test (Phase 2).
@objc public protocol HelperProtocol {
    func version(reply: @escaping @Sendable (String) -> Void)

    /// Replaces `/etc/hosts` with `content` if its current SHA-256 equals `expectedSHA256`
    /// (otherwise fails with `HelperError.staleFile`). Backs up first, writes atomically, flushes the DNS cache.
    func writeHosts(_ content: String, expectedSHA256: String, reply: @escaping @Sendable (NSError?) -> Void)
}
