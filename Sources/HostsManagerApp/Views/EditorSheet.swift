import SwiftUI

/// Add / Edit sheet. Phase 1: fields only, Save disabled.
struct EditorSheet: View {
    @Bindable var editor: EditorViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(editor.titleKey)).font(.headline)

            Form {
                TextField(localized("label.ip"), text: $editor.ip, prompt: Text(localized("placeholder.ip")))
                    .font(.system(.body, design: .monospaced))
                TextField(
                    localized("label.hostnames"),
                    text: $editor.hostnamesText,
                    prompt: Text(localized("placeholder.hostnames"))
                )
                .font(.system(.body, design: .monospaced))
                Text(localized("editor.hostnamesHint")).font(.caption).foregroundStyle(.secondary)
                TextField(
                    localized("label.comment"),
                    text: $editor.comment,
                    prompt: Text(localized("placeholder.comment"))
                )
            }

            HStack {
                Spacer()
                Button(localized("btn.cancel"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                // Phase 2: validate + write through the helper.
                Button(localized("btn.save")) {}
                    .keyboardShortcut(.defaultAction)
                    .disabled(true)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}
