import Foundation
import Observation
import Shared

/// Form state + live validation for the Add / Edit sheet.
@MainActor
@Observable
final class EditorViewModel: Identifiable {
    /// The entry being edited, `nil` when adding.
    let original: HostEntry?
    var ip: String
    /// Space-separated, as typed.
    var hostnamesText: String
    var comment: String
    private(set) var isGenerating = false
    var generateError: String?

    init(entry: HostEntry? = nil) {
        original = entry
        ip = entry?.ip ?? ""
        hostnamesText = entry?.hostnames.joined(separator: " ") ?? ""
        comment = entry?.comment ?? ""
    }

    var isEditing: Bool { original != nil }

    var titleKey: String { isEditing ? "editor.editTitle" : "editor.addTitle" }

    var hostnames: [String] { hostnamesText.split(whereSeparator: \.isWhitespace).map(String.init) }

    private var trimmedIP: String { ip.trimmingCharacters(in: .whitespaces) }

    /// Shown under the IP field once something is typed.
    var ipError: String? {
        trimmedIP.isEmpty || Validation.isIP(trimmedIP) ? nil : localized("err.invalidIP")
    }

    var hostnamesError: String? {
        hostnames.first { !Validation.isHostname($0) }.map { localized("err.invalidHostname", $0) }
    }

    var canSave: Bool {
        !trimmedIP.isEmpty && !hostnames.isEmpty && ipError == nil && hostnamesError == nil
    }

    var canGenerate: Bool { !hostnames.isEmpty && hostnamesError == nil && !isGenerating }

    /// Only this entry goes to the AI provider — not the rest of /etc/hosts.
    static func commentPrompt(ip: String, hostnames: [String]) -> (system: String, question: String) {
        (
            "You write the inline comment for one /etc/hosts entry: what it is for, at most 6 words. "
                + "Reply with the comment text only — no quotes, no #, no explanation.",
            "\(ip.isEmpty ? "127.0.0.1" : ip) \(hostnames.joined(separator: " "))"
        )
    }

    /// ✨ Generate Comment — same AI provider as the AI Agent panel.
    func generateComment() {
        let settings = AISettings.load()
        guard settings.isConfigured else { return generateError = localized("chat.noApiKey") }
        let prompt = Self.commentPrompt(ip: trimmedIP, hostnames: hostnames)
        isGenerating = true
        generateError = nil
        Task {
            do {
                let reply = try await AIService.complete(
                    settings, system: prompt.system, turns: [ChatTurn(role: .user, text: prompt.question)]
                )
                // first line only, no quotes, capped — the model's text is untrusted
                let firstLine = reply.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                let clean = HostEntry.oneLine(firstLine).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                comment = String(clean.prefix(80))
            } catch {
                generateError = error.localizedDescription
            }
            isGenerating = false
        }
    }

    /// The entry to write; keeps the original's id and enabled state when editing. `nil` while invalid.
    func makeEntry() -> HostEntry? {
        guard canSave else { return nil }
        let note = HostEntry.oneLine(comment)
        return HostEntry(
            id: original?.id ?? UUID(),
            ip: trimmedIP,
            hostnames: hostnames,
            comment: note.isEmpty ? nil : note,
            isEnabled: original?.isEnabled ?? true
        )
    }
}
