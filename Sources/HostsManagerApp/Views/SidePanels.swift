import SwiftUI

// Right-column panels of HostsView: AI Agent (ChatPanel.swift), Help (same as git-exclude-manager's SidePanels).
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

// MARK: - Help

struct HelpPanel: View {
    @Binding var isCollapsed: Bool
    var panelBackground = Color(.windowBackgroundColor)
    /// Shown alone in a tool window (redesign D): no fold header — the window has its own title.
    var isToolWindow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isToolWindow {
                HStack {
                    CollapseToggle(title: localized("menu.help"), isCollapsed: $isCollapsed)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if !isCollapsed {
                ScrollView { HelpList() }
                    .frame(maxHeight: .infinity)
            }
        }
        .background(panelBackground)
    }
}

/// Help topics in workflow order: setup (helper) → add / edit → organize → whole-file actions → AI.
struct HelpList: View {
    static let items: [(icon: String, key: String)] = [
        ("lock.shield", "help.helper"),
        ("plus.circle", "help.add"),
        ("checkmark.circle", "help.toggle"),
        ("magnifyingglass", "help.search"),
        ("text.badge.plus", "help.sections"),
        ("line.3.horizontal", "help.reorder"),
        ("lock", "help.system"),
        ("arrow.down.doc", "help.import"),
        ("clock.arrow.circlepath", "help.restore"),
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
