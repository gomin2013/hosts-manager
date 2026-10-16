import SwiftUI

/// Add / Edit sheet with live validation. Save is enabled only for a valid IP + hostnames.
struct EditorSheet: View {
    @Bindable var editor: EditorViewModel
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(editor.titleKey)).font(.headline)

            Form {
                TextField(localized("label.ip"), text: $editor.ip, prompt: Text(localized("placeholder.ip")))
                    .font(.system(.body, design: .monospaced))
                if let error = editor.ipError { errorText(error) }

                TextField(
                    localized("label.hostnames"),
                    text: $editor.hostnamesText,
                    prompt: Text(localized("placeholder.hostnames"))
                )
                .font(.system(.body, design: .monospaced))
                Text(localized("editor.hostnamesHint")).font(.caption).foregroundStyle(.secondary)
                if let error = editor.hostnamesError { errorText(error) }

                TextField(
                    localized("label.comment"),
                    text: $editor.comment,
                    prompt: Text(localized("placeholder.comment"))
                )
                HStack(spacing: 6) {
                    Button(action: editor.generateComment) {
                        Label(localized("btn.generateComment"), systemImage: "sparkles")
                    }
                    .controlSize(.small)
                    .disabled(!editor.canGenerate)
                    .help(localized("hint.generateComment"))
                    if editor.isGenerating { ProgressView().controlSize(.small) }
                }
                if let error = editor.generateError { errorText(error) }
            }

            HStack {
                Spacer()
                Button(localized("btn.cancel"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(localized("btn.save"), action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!editor.canSave)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private func errorText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.red)
    }
}
