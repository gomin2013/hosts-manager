import Foundation
import Observation

/// Runtime en/th switching without restarting the app. Views re-render on change because `localized(_:)`
/// reads `bundle`, which Observation tracks.
@MainActor
@Observable
final class LanguageService {
    enum Language: String, CaseIterable, Identifiable {
        case english = "en"
        case thai = "th"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .english: "🇺🇸 English"
            case .thai: "🇹🇭 ไทย"
            }
        }
    }

    static let shared = LanguageService()
    static let preferenceKey = "app.language"

    var current: Language {
        didSet {
            defaults.set(current.rawValue, forKey: Self.preferenceKey)
            bundle = Self.bundle(for: current)
        }
    }

    private(set) var bundle: Bundle
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.preferenceKey).flatMap(Language.init(rawValue:))
        let system: Language = (Locale.preferredLanguages.first ?? "en").hasPrefix("th") ? .thai : .english
        current = saved ?? system
        bundle = Self.bundle(for: saved ?? system)
    }

    func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func bundle(for language: Language) -> Bundle {
        // The .app ships the .lproj folders in Contents/Resources. Under `swift run` / `swift test` there is no app
        // bundle, so use SwiftPM's resource bundle (never touched from a .app: Bundle.module traps if it's missing).
        let resources = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        guard let path = resources.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

/// `Text(localized("btn.add"))`
@MainActor
func localized(_ key: String) -> String {
    LanguageService.shared.localized(key)
}

/// `localized("status.entries", total, enabled)` — `String(format:)` placeholders (`%@`, `%ld`).
@MainActor
func localized(_ key: String, _ args: CVarArg...) -> String {
    String(format: LanguageService.shared.localized(key), arguments: args)
}
