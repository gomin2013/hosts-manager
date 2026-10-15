import SwiftUI

@main
struct HostsManagerApp: App {
    @State private var hostsVM = HostsViewModel()

    var body: some Scene {
        // Regular Dock / Launchpad app (same as git-exclude-manager): ⌘Q / ⌘W come from the standard app menu.
        WindowGroup(localized("app.title")) {
            HostsView()
                .environment(hostsVM)
                .frame(minWidth: 760, minHeight: 540)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // One main window: drop File › New Window so ⌘N belongs to "Add Entry" (on its button in HostsView).
            CommandGroup(replacing: .newItem) {}
        }
    }
}
