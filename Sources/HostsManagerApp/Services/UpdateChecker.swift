import AppKit
import Foundation

/// The fields of GitHub's `releases/latest` that Check for Updates reads.
struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let url: URL
        enum CodingKeys: String, CodingKey { case name, url = "browser_download_url" }
    }
    let tag: String
    let page: URL
    let notes: String?
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case tag = "tag_name", page = "html_url", notes = "body", assets }

    var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
    var download: URL { assets.first { $0.name.hasSuffix(".dmg") }?.url ?? page }
}

/// App menu › Check for Updates… and the About panel. Asks GitHub for the latest *published* release (`releases/latest`
/// skips drafts and pre-releases), so publishing the draft is what makes an update show up. No Sparkle (zero deps):
/// Download opens the DMG in the browser and the user replaces the app as on first install.
/// Manual by default — the privacy page promises no background checks unless the user turns on `autoKey`.
@MainActor
enum UpdateChecker {
    struct HTTPStatus: LocalizedError {
        let code: Int
        var errorDescription: String? { "GitHub HTTP \(code)" }   // 403 = rate limit (60 checks an hour per IP)
    }

    nonisolated static let latest = URL(string: "https://api.github.com/repos/gomin2013/hosts-manager/releases/latest")!
    nonisolated static let releases = URL(string: "https://github.com/gomin2013/hosts-manager/releases")!
    static let autoKey = "update.auto", lastKey = "update.lastCheck", skipKey = "update.skip"
    private static var checking = false

    /// Numeric, never a plain string compare: as strings "1.1.10" < "1.1.9".
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }

    nonisolated static func decode(_ data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// At launch, at most once a day, and only when the user turned it on in About.
    static func checkIfDue() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: autoKey) else { return }
        if let last = defaults.object(forKey: lastKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        await check(manual: false)
    }

    /// `manual` (the user clicked) always answers. Automatic only speaks up for a new version that wasn't skipped.
    static func check(manual: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        do {
            var request = URLRequest(url: latest, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw HTTPStatus(code: http.statusCode)
            }
            let release = try decode(data)
            UserDefaults.standard.set(Date(), forKey: lastKey)
            if !isNewer(release.version, than: current) {
                if manual { upToDate(current) }
            } else if manual || UserDefaults.standard.string(forKey: skipKey) != release.version {
                available(release, current: current, canSkip: !manual)
            }
        } catch {
            if manual { failed(error) }
        }
    }

    // MARK: - Alerts (Platypus / Sparkle look: app icon, one line, one decision)

    private static func alert(_ title: String, _ text: String) -> NSAlert {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = title
        alert.informativeText = text
        return alert
    }

    private static func upToDate(_ current: String) {
        let alert = alert(localized("update.upToDate.title"),
                          localized("update.upToDate.body", localized("app.title"), current))
        alert.addButton(withTitle: localized("update.ok"))
        alert.runModal()
    }

    private static func available(_ release: GitHubRelease, current: String, canSkip: Bool) {
        let alert = alert(localized("update.available.title", localized("app.title")),
                          localized("update.available.body", release.version, current))
        alert.accessoryView = notesView(release.notes)
        alert.addButton(withTitle: localized("update.download"))
        alert.addButton(withTitle: localized("update.later"))
        if canSkip { alert.addButton(withTitle: localized("update.skip")) }
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.download)
        case .alertThirdButtonReturn: UserDefaults.standard.set(release.version, forKey: skipKey)
        default: break
        }
    }

    private static func failed(_ error: Error) {
        let alert = alert(localized("update.failed.title"), error.localizedDescription)
        alert.addButton(withTitle: localized("update.ok"))
        alert.addButton(withTitle: localized("update.openReleases"))
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(releases) }
    }

    /// CHANGELOG Markdown → plain text: the `## v1.1.4 — date` line repeats the alert's title, `### Fixed` → `Fixed`.
    nonisolated static func plainNotes(_ notes: String) -> String {
        notes.replacingOccurrences(of: "**", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("## ") }
            .map { $0.hasPrefix("### ") ? String($0.dropFirst(4)) : String($0) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The release notes (= the CHANGELOG section) in a small scrollable box. ponytail: plain text via `plainNotes`;
    /// render Markdown here if the notes start relying on links.
    private static func notesView(_ notes: String?) -> NSView? {
        guard let notes, !notes.isEmpty else { return nil }
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 380, height: 200)
        guard let text = scroll.documentView as? NSTextView else { return nil }
        text.string = plainNotes(notes)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .labelColor
        text.isEditable = false
        return scroll
    }
}
