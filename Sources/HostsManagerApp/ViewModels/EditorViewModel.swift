import Foundation
import Observation
import Shared

/// Form state for the Add / Edit sheet. Phase 2 adds validation and saving.
@MainActor
@Observable
final class EditorViewModel: Identifiable {
    /// The entry being edited, `nil` when adding.
    let original: HostEntry?
    var ip: String
    /// Space-separated, as typed.
    var hostnamesText: String
    var comment: String

    init(entry: HostEntry? = nil) {
        original = entry
        ip = entry?.ip ?? ""
        hostnamesText = entry?.hostnames.joined(separator: " ") ?? ""
        comment = entry?.comment ?? ""
    }

    var isEditing: Bool { original != nil }

    var titleKey: String { isEditing ? "editor.editTitle" : "editor.addTitle" }

    var hostnames: [String] { hostnamesText.split(whereSeparator: \.isWhitespace).map(String.init) }
}
