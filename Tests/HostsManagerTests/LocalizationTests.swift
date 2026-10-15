import XCTest
import Shared
@testable import HostsManagerApp

/// en and th must have identical keys, and every key the prototype (`shared.js`) or `HelperError` uses must exist.
@MainActor
final class LocalizationTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func keys(_ lang: String) throws -> Set<String> {
        let url = Self.root
            .appendingPathComponent("Sources/HostsManagerApp/Resources/\(lang).lproj/Localizable.strings")
        let dict = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(lang) strings unreadable")
        return Set(dict.keys)
    }

    func testEnglishAndThaiHaveTheSameKeys() throws {
        let english = try keys("en"), thai = try keys("th")
        XCTAssertEqual(english.subtracting(thai), [], "missing in th")
        XCTAssertEqual(thai.subtracting(english), [], "missing in en")
    }

    func testPrototypeKeysExist() throws {
        let url = Self.root.appendingPathComponent(".prototype/javascripts/shared.js")
        let js = try String(contentsOf: url, encoding: .utf8)
        let prototypeKeys = Set(js.matches(of: /"([a-z]+\.[A-Za-z.]+)":/).map { String($0.output.1) })
        XCTAssertFalse(prototypeKeys.isEmpty)
        XCTAssertEqual(prototypeKeys.subtracting(try keys("en")), [])
    }

    func testHelperErrorKeysExist() throws {
        let english = try keys("en")
        for error in HelperError.allCases {
            XCTAssertTrue(english.contains(error.localizationKey), error.localizationKey)
        }
    }

    func testEveryLiteralKeyUsedInSourcesExists() throws {
        let english = try keys("en")
        let sources = Self.root.appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        var used = Set<String>()
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8)
            used.formUnion(code.matches(of: /localized\("([a-z]+\.[A-Za-z.]+)"/).map { String($0.output.1) })
        }
        XCTAssertGreaterThan(used.count, 40)
        XCTAssertEqual(used.subtracting(english), [])
    }

    func testHelpTopicsAndQuickMessagesExist() throws {
        let english = try keys("en")
        let helpKeys = HelpList.items.flatMap { [$0.key + ".title", $0.key + ".desc"] }
        for key in helpKeys + ChatPanel.quickMessageKeys {
            XCTAssertTrue(english.contains(key), key)
        }
    }

    func testRuntimeLookupSwitchesLanguage() {
        let service = LanguageService(defaults: UserDefaults(suiteName: "LocalizationTests")!)
        service.current = .english
        XCTAssertEqual(service.localized("btn.save"), "Save")
        service.current = .thai
        XCTAssertEqual(service.localized("btn.save"), "บันทึก")
        XCTAssertEqual(service.localized("no.such.key"), "no.such.key")
    }
}
