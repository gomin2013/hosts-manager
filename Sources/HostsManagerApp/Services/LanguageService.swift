import Foundation
import Observation

/// Runtime language switching without restarting the app. Views re-render on change because `localized(_:)`
/// reads `bundle`, which Observation tracks. A key missing from a language falls back to English, never the raw key.
@MainActor
@Observable
final class LanguageService {
    /// Same enum in git-exclude-manager (`LanguageService.Language`) — keep both in sync until DevFileKit.
    enum Language: String, CaseIterable, Identifiable {
        case english = "en", thai = "th", japanese = "ja", korean = "ko", vietnamese = "vi"
        case indonesian = "id", malay = "ms", filipino = "tl"
        case chineseSimplified = "zh-Hans", chineseTraditional = "zh-Hant", spanish = "es", russian = "ru"

        var id: String { rawValue }

        /// The language's own name — what a speaker looks for in a list.
        var nativeName: String {
            switch self {
            case .english: "English"
            case .thai: "ไทย"
            case .japanese: "日本語"
            case .korean: "한국어"
            case .vietnamese: "Tiếng Việt"
            case .indonesian: "Bahasa Indonesia"
            case .malay: "Bahasa Melayu"
            case .filipino: "Filipino"
            case .chineseSimplified: "简体中文"
            case .chineseTraditional: "繁體中文"
            case .spanish: "Español"
            case .russian: "Русский"
            }
        }

        /// English name: the AI is told to "Reply in <englishName>", and search matches it.
        var englishName: String {
            switch self {
            case .english: "English"
            case .thai: "Thai"
            case .japanese: "Japanese"
            case .korean: "Korean"
            case .vietnamese: "Vietnamese"
            case .indonesian: "Indonesian"
            case .malay: "Malay"
            case .filipino: "Filipino"
            case .chineseSimplified: "Simplified Chinese"
            case .chineseTraditional: "Traditional Chinese"
            case .spanish: "Spanish"
            case .russian: "Russian"
            }
        }

        var flag: String {
            switch self {
            case .english: "🇺🇸"
            case .thai: "🇹🇭"
            case .japanese: "🇯🇵"
            case .korean: "🇰🇷"
            case .vietnamese: "🇻🇳"
            case .indonesian: "🇮🇩"
            case .malay: "🇲🇾"
            case .filipino: "🇵🇭"
            case .chineseSimplified: "🇨🇳"
            case .chineseTraditional: "🇹🇼"
            case .spanish: "🇪🇸"
            case .russian: "🇷🇺"
            }
        }

        var displayName: String { flag + " " + nativeName }

        /// The language's name written in `other` ("ญี่ปุ่น" for Japanese when the UI is Thai), from Foundation.
        func name(in other: Language) -> String {
            Locale(identifier: other.rawValue).localizedString(forIdentifier: rawValue) ?? englishName
        }

        /// Search: native name, English name, the name in the current UI language, or the code ("ja", "zh").
        func matches(_ query: String, uiLanguage: Language) -> Bool {
            let query = query.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return true }
            return [nativeName, englishName, name(in: uiLanguage), rawValue]
                .contains { $0.localizedStandardContains(query) }
        }

        /// First supported language in the user's macOS list ("zh-TW" → Traditional, "fil-PH" → Filipino), else English.
        static func preferred(from identifiers: [String]) -> Language {
            for identifier in identifiers {
                let code = identifier.lowercased()
                if code.hasPrefix("zh") {
                    let traditional = ["hant", "-tw", "-hk", "-mo"].contains { code.contains($0) }
                    return traditional ? .chineseTraditional : .chineseSimplified
                }
                if code.hasPrefix("fil") { return .filipino }
                let base = String(code.prefix { $0 != "-" && $0 != "_" })
                if let match = allCases.first(where: { $0.rawValue == base }) { return match }
            }
            return .english
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
    @ObservationIgnored private let english: Bundle
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        english = Self.bundle(for: .english)
        let saved = defaults.string(forKey: Self.preferenceKey).flatMap(Language.init(rawValue:))
        let language = saved ?? Language.preferred(from: Locale.preferredLanguages)
        current = language
        bundle = Self.bundle(for: language)
    }

    func localized(_ key: String) -> String {
        let missing = "\u{0}"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        return value == missing ? english.localizedString(forKey: key, value: key, table: nil) : value
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
