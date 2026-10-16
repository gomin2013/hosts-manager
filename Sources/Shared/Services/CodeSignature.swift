import Foundation
import Security

public enum CodeSignature {
    /// Hex cdhash of a signed, intact `.app` (its main executable), or `nil` otherwise.
    /// The helper pins clients to it (ADR-010).
    public static func cdhash(ofAppAt url: URL) -> String? {
        guard url.pathExtension == "app" else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let unique = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }
}
