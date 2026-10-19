import SwiftUI
import Shared

// Same structure as git-exclude-manager's ToolWindow.swift (keep in sync until DevFileKit) — the panels differ.
// Right-hand tool window like JetBrains IDEs: an icon rail on the window edge, one panel at a time at full height,
// "–" hides it. Replaces the stacked fold-out panels (audit #10). Plus gradient themes as ambient light.

/// The panels the rail switches between. ⌥⌘1…5 toggle them (git-exclude-manager adds Clipboard and Suggestions).
enum ToolPanel: String, CaseIterable, Identifiable {
    case history, agent, help, appearance, language, about

    /// Pinned to the bottom of the rail. Settings is split into Language and About for now (may come back as one).
    static let bottom: [ToolPanel] = [.appearance, .language, .about]

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .agent: "sparkles"
        case .help: "questionmark.circle"
        case .appearance: "paintpalette"
        case .language: "globe"
        case .about: "info.circle"
        }
    }

    @MainActor var title: String {
        switch self {
        case .history: localized("history.title")
        case .agent: localized("chat.title")
        case .help: localized("menu.help")
        case .appearance: localized("settings.appearance")
        case .language: localized("settings.language")
        case .about: localized("menu.about")
        }
    }
}

/// Two-tone gradients from the user's reference (Pinterest "8 color schemes"). Measured: no pair keeps white text
/// ≥ 4.5:1 end to end (one end is 1.06–1.6:1) and some ends vanish on a dark window (#251351 is 1.02:1), so a theme
/// is **ambient light only** — never under text or controls. Controls take the paired solid accent instead.
enum GradientTheme: String, CaseIterable, Identifiable {
    case none, ocean, ember, lavender, watermelon, lagoon, meadow, dusk, peach

    var id: String { rawValue }
    @MainActor var name: String { localized("gradient." + rawValue) }

    var colors: [Color] {
        let pair: (UInt32, UInt32) = switch self {
        case .none: (0, 0)
        case .ocean: (0x007CBE, 0xFFF7AE)
        case .ember: (0xE57A44, 0x251351)
        case .lavender: (0xF1FEC6, 0xA882DD)
        case .watermelon: (0xDB5375, 0xB3FFB3)
        case .lagoon: (0x02C3BD, 0x4E148C)
        case .meadow: (0x629460, 0xF4D35E)
        case .dusk: (0x414288, 0xB0DB43)
        case .peach: (0xFFC145, 0xEC368D)
        }
        return [Self.color(pair.0), Self.color(pair.1)]
    }

    /// Solid accent for controls — the palette hue closest to the gradient's stronger end.
    var accent: AccentChoice {
        switch self {
        case .none: .system
        case .ocean: .blue
        case .ember: .orange
        case .lavender: .violet
        case .watermelon: .pink
        case .lagoon: .teal
        case .meadow: .lime
        case .dusk: .indigo
        case .peach: .magenta
        }
    }

    /// `-gradient lagoon` for screenshots.
    static var launchOverride: GradientTheme? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-gradient"), args.indices.contains(index + 1) else { return nil }
        return GradientTheme(rawValue: args[index + 1])
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

/// Panel (when open) + icon rail on the trailing edge.
struct ToolWindow: View {
    @Binding var panel: ToolPanel?
    let theme: GradientTheme
    /// History restores write the file — off while the helper isn't approved or a save is in flight.
    var canWrite = true
    @Environment(HostsViewModel.self) private var vm
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // Every panel stays mounted (hidden, zero-width when closed): the AI Agent's conversation is view state and
        // would be lost on each switch otherwise.
        HStack(spacing: 0) {
            window
                .frame(width: panel == nil ? 0 : 320)
                .opacity(panel == nil ? 0 : 1)
                .allowsHitTesting(panel != nil)
                .accessibilityHidden(panel == nil)
            rail
        }
    }

    private var rail: some View {
        VStack(spacing: 6) {
            ForEach(ToolPanel.allCases.filter { !ToolPanel.bottom.contains($0) }) { railButton($0) }
            Spacer()
            ForEach(ToolPanel.bottom) { railButton($0) }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .overlay(alignment: .leading) { Divider() }
    }

    private func railButton(_ item: ToolPanel) -> some View {
        let number = (ToolPanel.allCases.firstIndex(of: item) ?? 0) + 1
        return Button { panel = panel == item ? nil : item } label: {
            Image(systemName: item.icon)
                .font(.system(size: 15))
                .frame(width: 32, height: 32)
                .foregroundStyle(panel == item ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .background(panel == item ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: [.command, .option])
        .help(localized("hint.withShortcut", item.title, "⌥⌘\(number)"))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(panel == item ? .isSelected : [])
    }

    private var window: some View {
        let shown = panel ?? .agent
        return VStack(spacing: 0) {
            HStack {
                Text(shown.title).font(.app(13, .semibold))
                Spacer()
                Button { panel = nil } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless)
                    .help(localized("btn.hide"))
                    .accessibilityLabel(localized("a11y.hidePanel", shown.title))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
            ZStack {
                ForEach(ToolPanel.allCases) { item in
                    VStack(spacing: 0) { content(item) }
                        .opacity(item == shown ? 1 : 0)
                        .allowsHitTesting(item == shown)
                        .accessibilityHidden(item != shown)
                }
            }
        }
        .background(alignment: .bottomTrailing) { glow }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .glassSurface(cornerRadius: 18)
        .padding(10)
    }

    @ViewBuilder
    private func content(_ item: ToolPanel) -> some View {
        switch item {
        case .history:
            HistoryPanel(isCollapsed: .constant(false), canWrite: canWrite, panelBackground: .clear,
                         isToolWindow: true)
        case .agent:
            ChatPanel(hostsText: vm.rawText, isCollapsed: .constant(false), panelBackground: .clear,
                      isToolWindow: true)
        case .help:
            HelpPanel(isCollapsed: .constant(false), panelBackground: .clear, isToolWindow: true)
        case .appearance:
            AppearancePanel()
        case .language:
            LanguagePanel()
        case .about:
            AboutPanel()
        }
        Spacer(minLength: 0)
    }

    /// Ambient light in the panel's corner, like the reference. Off with Reduce Transparency.
    @ViewBuilder
    private var glow: some View {
        if theme != .none && !reduceTransparency {
            Ellipse()
                .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 340, height: 280)
                .blur(radius: 60)
                .opacity(0.75)
                .offset(x: 110, y: 110)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
