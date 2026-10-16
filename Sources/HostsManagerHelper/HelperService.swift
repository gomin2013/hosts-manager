import Foundation
import Shared

/// XPC-exported object. Every reply is called exactly once.
final class HelperService: NSObject, HelperProtocol, Sendable {
    private let writer: HostsWriter

    init(writer: HostsWriter = HostsWriter()) {
        self.writer = writer
    }

    func version(reply: @escaping @Sendable (String) -> Void) {
        reply(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
    }

    func writeHosts(_ content: String, expectedSHA256: String, reply: @escaping @Sendable (NSError?) -> Void) {
        do {
            try writer.write(content, expectedSHA256: expectedSHA256)
            reply(nil)
        } catch {
            reply(error.nsError)
        }
    }
}

/// Accepts only the Hosts Manager app this helper ships inside (ADR-010).
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    /// The app bundle the helper runs from: launchd starts `…/HostsManager.app/Contents/MacOS/HostsManagerHelper`,
    /// so `Bundle.main` is the app.
    var appURL = Bundle.main.bundleURL

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Fail closed: no requirement we can trust → no connection.
        guard let requirement = Self.requirement(forAppAt: appURL) else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }

    // ponytail: with Developer ID, switch to `anchor apple generic … certificate leaf[subject.OU] = "<TEAMID>"` (Phase 4)
    /// `identifier` alone is spoofable (ad-hoc signatures can claim any identifier), so also pin the exact cdhash of
    /// the installed app, read from disk at connection time — no Developer ID needed, and it can't be circular the
    /// way a hash baked into the helper would be. The kernel checks the client against it (audit token).
    static func requirement(forAppAt url: URL) -> String? {
        guard let cdhash = CodeSignature.cdhash(ofAppAt: url) else { return nil }
        return "identifier \"\(HelperConstants.appBundleIdentifier)\" and cdhash H\"\(cdhash)\""
    }
}
