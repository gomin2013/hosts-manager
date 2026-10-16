import Foundation
import Observation
import ServiceManagement
import Shared

/// Registers the bundled LaunchDaemon (`Contents/Library/LaunchDaemons/com.hostsmanager.helper.plist`) and reports
/// whether it can be used. macOS asks the user to allow it once in System Settings → General → Login Items.
@MainActor
@Observable
final class HelperInstaller {
    enum Status: Equatable {
        /// Not a .app bundle (`swift run` / tests) — SMAppService can't register anything.
        case unavailable
        case notRegistered
        case requiresApproval
        case ready
    }

    private(set) var status: Status = .unavailable

    var statusKey: String {
        switch status {
        case .unavailable: "helper.unavailable"
        case .notRegistered: "helper.notInstalled"
        case .requiresApproval: "helper.needsApproval"
        case .ready: "helper.ready"
        }
    }

    private var service: SMAppService? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
    }

    /// Called at launch: registers if needed, then reports the status.
    /// Never unregister + register to "refresh" it: launchd is then left with a stale launch constraint
    /// (`needs LWCR update` → "Could not find … program", EX_CONFIG) until the user re-approves — verified
    /// 2026-10-16. A rebuilt / updated app keeps working without it.
    func registerIfNeeded() {
        guard let service else { return status = .unavailable }
        if service.status == .notRegistered || service.status == .notFound {
            do {
                try service.register()
            } catch {
                NSLog("Helper registration failed: \(error.localizedDescription)")
            }
        }
        refresh()
    }

    /// The user may approve in System Settings at any time — re-read when the app becomes active.
    func refresh() {
        guard let service else { return status = .unavailable }
        status = switch service.status {
        case .enabled: .ready
        case .requiresApproval: .requiresApproval
        default: .notRegistered
        }
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
