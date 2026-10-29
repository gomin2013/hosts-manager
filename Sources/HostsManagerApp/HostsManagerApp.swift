import SwiftUI

@main
struct HostsManagerApp: App {
    /// `open HostsManager.app --args -demo` shows MockData; edits stay in memory — screenshots and recordings without real hostnames.
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
                .task {
                    // `-demo` never writes, so it never registers the helper either: a demo run of a build copy
                    // can't replace the installed app's LaunchDaemon registration.
                    if !hostsVM.isDemo { installer.registerIfNeeded() }
                    // 1432×972 near the top-left for scripts/capture-screenshots.sh — the size the website's (and
                    // gomin2013.github.io's) <img width/height> expect. Moving another app's window from a script
                    // would need Accessibility access. After a beat: on attach the window isn't visible yet and window
                    // restoration would put the old frame back.
                    if hostsVM.isDemo { try? await Task.sleep(for: .milliseconds(300)) }
                    if hostsVM.isDemo, let window = NSApp.windows.first(where: \.isVisible),
                       let screen = window.screen ?? NSScreen.main {
                        let frame = NSRect(x: screen.visibleFrame.minX + 60, y: screen.visibleFrame.maxY - 992,
                                           width: 1432, height: 972)
                        window.setFrame(frame, display: true)
                    }
                    #if DEBUG
                    hostsVM.seedDemoHistory()
                    hostsVM.openDemoEditor()
                    #endif
                }
                // Off unless turned on in About; never in `-demo` (an alert would land in screenshots)
                .task { if !hostsVM.isDemo { await UpdateChecker.checkIfDue() } }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(localized("update.check")) { Task { await UpdateChecker.check(manual: true) } }
            }
            // One main window: drop File › New Window so ⌘N belongs to "Add Entry" (on its button in HostsView).
            CommandGroup(replacing: .newItem) {}
            // Help › Hosts Manager Help (⌘?) opens the Help panel instead of an empty Help Book search
            CommandGroup(replacing: .help) {
                Button(localized("menu.helpWindow")) {
                    UserDefaults.standard.set(ToolPanel.help.rawValue, forKey: "ui.toolPanel")
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}
