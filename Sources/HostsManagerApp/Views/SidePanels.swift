import SwiftUI

// Right-column panels of HostsView: AI Agent, Help (same as git-exclude-manager's SidePanels).
// Each folds with a CollapseToggle; HostsView owns the folded flags (@AppStorage) and the layout.

/// ▸/▾ + title; click folds the panel.
struct CollapseToggle: View {
    let title: String
    @Binding var isCollapsed: Bool

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) { isCollapsed.toggle() }
        }, label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 10)
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
            }
            .contentShape(Rectangle())
        })
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(localized(isCollapsed ? "a11y.collapsed" : "a11y.expanded"))
        .accessibilityHint(localized("a11y.toggleHint"))
    }
}

// MARK: - AI Agent

/// Chat about this Mac's hosts file. Phase 1: layout only — provider settings and AIService land in Phase 3.
struct ChatPanel: View {
    @Binding var isCollapsed: Bool

    @State private var input = ""

    static let quickMessageKeys = [
        "quick.explain", "quick.conflicts", "quick.block", "quick.localDev", "quick.organize"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isCollapsed {
                Divider()
                transcript
                Divider()
                quickMessages
                inputRow
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                CollapseToggle(title: localized("chat.title"), isCollapsed: $isCollapsed)
                Text(localized("ai.notConfigured"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.orange)
                    .padding(.leading, 16)  // align under the title, past the chevron
            }
            Spacer()
            Button(action: {}, label: { Image(systemName: "gearshape") })
                .buttonStyle(.borderless)
                .disabled(true)
                .help(localized("settings.title"))
                .accessibilityLabel(localized("settings.title"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("chat.welcome"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(localized("chat.noApiKey"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
    }

    /// One-tap example prompts above the input.
    private var quickMessages: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            ForEach(Self.quickMessageKeys, id: \.self) { key in
                Button(action: {}, label: {
                    // plain + custom background: bordered macOS buttons never wrap
                    Text(localized(key))
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField(localized("chat.placeholder"), text: $input)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(localized("chat.placeholder"))
            Button(localized("btn.send")) {}
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .disabled(true)
        .padding(10)
    }
}

// MARK: - Help

struct HelpPanel: View {
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CollapseToggle(title: localized("menu.help"), isCollapsed: $isCollapsed)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !isCollapsed {
                ScrollView { HelpList() }
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Color(.windowBackgroundColor))
    }
}

/// Help topics. Order follows the workflow: build content, edit rows, whole-file actions, then helpers.
struct HelpList: View {
    static let items: [(icon: String, key: String)] = [
        ("plus.circle", "help.add"),
        ("text.badge.plus", "help.sections"),
        ("checkmark.circle", "help.toggle"),
        ("line.3.horizontal", "help.reorder"),
        ("lock", "help.system"),
        ("arrow.down.doc", "help.import"),
        ("arrow.uturn.backward", "help.restore"),
        ("eye", "help.preview"),
        ("sparkles", "help.ai")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.items, id: \.key) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.icon)
                        .frame(width: 18)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized(item.key + ".title")).font(.callout.bold())
                        Text(localized(item.key + ".desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}
