import AppKit
import SwiftUI
import Shared

/// Preview Raw: the file exactly as it would be written, with a Copy button.
struct RawPreviewView: View {
    let content: String
    var onDismiss: () -> Void = {}

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(localized("raw.title")).font(.headline)
                Spacer()
                // Same circle as CloseButton; flips to a green ✓ for 1.5 s after copying
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help(localized(copied ? "raw.copied" : "btn.copy") + " (⇧⌘C)")
                .accessibilityLabel(localized(copied ? "raw.copied" : "btn.copy"))

                CloseButton(action: onDismiss)
            }
            .padding(14)

            Divider()

            Text(HelperConstants.hostsPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))

            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 280)
            .background(Color(.textBackgroundColor))
        }
        .frame(width: 560)
        .background(Color(.windowBackgroundColor))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// ✕ in a circle, closes a sheet (Esc).
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help(localized("btn.close"))
        .accessibilityLabel(localized("btn.close"))
    }
}

/// Shown in the About panel of the tool window (Settings is split into Language / About for now).
struct AboutView: View {
    @AppStorage(UpdateChecker.autoKey) private var autoUpdate = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(localized("app.title")).font(.title2.bold())
            Text(localized("about.version", version))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(localized("update.check")) { Task { await UpdateChecker.check(manual: true) } }
            Toggle(localized("update.auto"), isOn: $autoUpdate)
                .font(.caption)
                .help(localized("update.auto.help"))
            Text(localized("about.desc"))
                .multilineTextAlignment(.center)
            Link(destination: URL(string: "https://github.com/sponsors/gomin2013")!) {
                Label(localized("about.support"), systemImage: "heart.fill")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
