import XCTest
@testable import HostsManagerApp

/// Every language ships every English key with the same `String(format:)` placeholders — a wrong or missing `%@`
/// crashes or garbles the UI. Plus system-language detection and the Language panel's search.
@MainActor
final class TranslationTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/HostsManagerApp/Resources")

    private func strings(_ code: String) throws -> [String: String] {
        let url = Self.resources.appendingPathComponent("\(code).lproj/Localizable.strings")
        let dict = NSDictionary(contentsOf: url) as? [String: String]
        return try XCTUnwrap(dict, "\(code) strings missing or unreadable")
    }

    /// `%@`, `%ld`, `%1$@`… in order; `%%` is a literal percent, not a placeholder.
    private func placeholders(_ text: String) -> [String] {
        text.replacing("%%", with: "").matches(of: /%(?:\d+\$)?(?:@|l?l?[dDuUxXfFeEgGcs])/).map { String($0.output) }
    }

    func testEveryLanguageHasEveryKeyWithTheSamePlaceholders() throws {
        let english = try strings("en")
        for language in LanguageService.Language.allCases where language != .english {
            let translated = try strings(language.rawValue)
            let code = language.rawValue
            XCTAssertEqual(Set(english.keys).subtracting(translated.keys).sorted(), [], "missing in \(code)")
            XCTAssertEqual(Set(translated.keys).subtracting(english.keys).sorted(), [], "extra in \(code)")
            for (key, value) in english {
                guard let other = translated[key] else { continue }
                XCTAssertEqual(placeholders(other).sorted(), placeholders(value).sorted(), "\(code) \(key)")
                XCTAssertFalse(other.trimmingCharacters(in: .whitespaces).isEmpty, "\(code) \(key) empty")
            }
        }
    }

    func testSystemLanguageDetection() {
        typealias Language = LanguageService.Language
        XCTAssertEqual(Language.preferred(from: ["th-TH", "en-US"]), .thai)
        XCTAssertEqual(Language.preferred(from: ["ja-JP"]), .japanese)
        XCTAssertEqual(Language.preferred(from: ["zh-Hant-TW"]), .chineseTraditional)
        XCTAssertEqual(Language.preferred(from: ["zh-HK"]), .chineseTraditional)
        XCTAssertEqual(Language.preferred(from: ["zh-Hans-CN"]), .chineseSimplified)
        XCTAssertEqual(Language.preferred(from: ["fil-PH"]), .filipino)
        XCTAssertEqual(Language.preferred(from: ["de-DE", "ko-KR"]), .korean, "first supported one wins")
        XCTAssertEqual(Language.preferred(from: ["de-DE"]), .english)
    }

    func testLanguageSearch() {
        typealias Language = LanguageService.Language
        func found(_ query: String, ui: Language = .english) -> [Language] {
            Language.allCases.filter { $0.matches(query, uiLanguage: ui) }
        }
        XCTAssertEqual(found(""), Language.allCases)
        XCTAssertEqual(found("日本"), [.japanese], "native name")
        XCTAssertEqual(found("japan"), [.japanese], "English name, any case")
        XCTAssertEqual(found("ญี่ปุ่น", ui: .thai), [.japanese], "name in the current UI language")
        XCTAssertEqual(Set(found("chinese")), [.chineseSimplified, .chineseTraditional])
        XCTAssertEqual(found("viet"), [.vietnamese])
        XCTAssertEqual(found("espanol"), [.spanish], "diacritics ignored")
        XCTAssertEqual(found("xyz"), [])
    }

    /// The Language panel and the website's language picker (`docs/assets/site.js`) list the 12 languages in one order.
    func testLanguageOrderMatchesTheWebsite() throws {
        let repo = Self.resources.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let js = try String(contentsOf: repo.appendingPathComponent("docs/assets/site.js"), encoding: .utf8)
        let list = try XCTUnwrap(js.firstMatch(of: /var LANGS = \[([\s\S]*?)\];/)?.output.1, "LANGS not found")
        let site = list.matches(of: /\["([\w-]+)",/).map { String($0.output.1) }
        let order = ["en", "th", "ja", "ko", "vi", "id", "ms", "tl", "zh-Hans", "zh-Hant", "es", "ru"]
        XCTAssertEqual(LanguageService.Language.allCases.map(\.rawValue), order)
        XCTAssertEqual(site, order)
    }
}
