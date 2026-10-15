import AppKit
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: "💻"
        case .light: "☀️"
        case .dark: "🌙"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// ⚙ Settings ▾ — Language / Appearance / About (same menu as git-exclude-manager's SettingsDropdownView).
struct SettingsMenu: View {
    var onAbout: () -> Void = {}

    @AppStorage("app.appearance") private var appearance: Appearance = .system

    var body: some View {
        @Bindable var language = LanguageService.shared
        Menu {
            // Inline pickers: native menu checkmarks + VoiceOver "selected" state
            Picker(localized("settings.language"), selection: $language.current) {
                ForEach(LanguageService.Language.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.inline)

            Divider()

            Picker(localized("settings.appearance"), selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.icon + " " + localized("appearance.\($0.rawValue)")).tag($0) }
            }
            .pickerStyle(.inline)

            Divider()

            // Help lives in the right-column panel
            Button(action: onAbout) {
                Label(localized("menu.about"), systemImage: "info.circle")
            }
        } label: {
            Label(localized("btn.settings"), systemImage: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(localized("btn.settings"))
        .onChange(of: appearance, initial: true) { NSApp.appearance = appearance.nsAppearance }
    }
}
