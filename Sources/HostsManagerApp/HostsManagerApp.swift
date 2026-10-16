import SwiftUI

@main
struct HostsManagerApp: App {
    /// `open HostsManager.app --args -demo` shows MockData read-only — README screenshots without real hostnames.
    @State private var hostsVM = CommandLine.arguments.contains("-demo")
        ? HostsViewModel(lines: MockData.lines)
        : HostsViewModel()
    @State private var installer = HelperInstaller()

    var body: some Scene {
        // Regular Dock / Launchpad app (same as git-exclude-manager): ⌘Q / ⌘W come from the standard app menu.
        WindowGroup(localized("app.title")) {
            HostsView()
                .environment(hostsVM)
                .environment(installer)
                .frame(minWidth: 760, minHeight: 540)
                .task { installer.registerIfNeeded() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            // One main window: drop File › New Window so ⌘N belongs to "Add Entry" (on its button in HostsView).
            CommandGroup(replacing: .newItem) {}
        }
    }
}
