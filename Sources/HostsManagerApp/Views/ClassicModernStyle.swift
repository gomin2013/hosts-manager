import SwiftUI

// Design tokens (v1.1 redesign "Classic Modern"): app font, accent palette, Liquid Glass with a material fallback.
// Same file in git-exclude-manager — candidates for DevFileKit.

// MARK: - Font

extension Font {
    /// Sukhumvit Set for interface text (Thai + Latin from one family); `-systemFont` compares with SF.
    /// Data (IPs, hostnames, raw lines) stays SF Mono — see `Font.data`.
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: TextStyle = .body) -> Font {
        guard !CommandLine.arguments.contains("-systemFont") else { return .system(size: size, weight: weight) }
        return .custom("Sukhumvit Set", size: size, relativeTo: style).weight(weight)
    }

    static func data(_ size: CGFloat = 13) -> Font { .system(size: size, design: .monospaced) }
}

// MARK: - Accent

/// 16 hues + System. Each colour sits at relative luminance ≈ 0.16, so white text on it is 5.0:1 and the colour on
/// a dark window (#1E1E1E) is 3.3:1 — one value works in light and dark, and filled buttons / selection stay legible.
/// More hues than 16 at that luminance become indistinguishable neighbours (Teal / Cyan / Emerald are already close).
enum AccentChoice: String, CaseIterable, Identifiable {
    case system
    case red, orange, amber, olive, lime, green, emerald, teal
    case cyan, blue, indigo, violet, purple, magenta, pink, graphite

    var id: String { rawValue }

    /// nil = the accent people chose in System Settings.
    var color: Color? {
        let hex: UInt32? = switch self {
        case .system: nil
        case .red: 0xE00219
        case .orange: 0xB45403
        case .amber: 0x9A6405
        case .olive: 0x7F7002
        case .lime: 0x557B04
        case .green: 0x028132
        case .emerald: 0x057F60
        case .teal: 0x077D7A
        case .cyan: 0x027A8F
        case .blue: 0x036AE4
        case .indigo: 0x5C55FF
        case .violet: 0x8F3DFA
        case .purple: 0xB424D8
        case .magenta: 0xCF01A6
        case .pink: 0xDB045E
        case .graphite: 0x6F6F6F
        }
        return hex.map {
            Color(.sRGB, red: Double($0 >> 16 & 0xFF) / 255, green: Double($0 >> 8 & 0xFF) / 255,
                  blue: Double($0 & 0xFF) / 255)
        }
    }

    @MainActor var name: String { localized("accent." + rawValue) }

    /// `-accent teal` for screenshots; otherwise the stored choice.
    static var launchOverride: AccentChoice? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-accent"), args.indices.contains(index + 1) else { return nil }
        return AccentChoice(rawValue: args[index + 1])
    }
}

/// System + 2 × 8 swatches, like System Settings › Appearance.
struct AccentPicker: View {
    @Binding var choice: AccentChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("theme.accent")).font(.app(13, .semibold))
            swatch(.system)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 10), count: 8), spacing: 10) {
                ForEach(AccentChoice.allCases.dropFirst()) { swatch($0, showsName: false) }
            }
            Text(choice.name).font(.app(12)).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func swatch(_ option: AccentChoice, showsName: Bool = true) -> some View {
        Button { choice = option } label: {
            HStack(spacing: 8) {
                ZStack {
                    if let color = option.color {
                        Circle().fill(color)
                    } else {
                        Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                                      center: .center))
                    }
                    if option == choice {
                        Circle().strokeBorder(.background, lineWidth: 2).padding(2)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                if showsName { Text(localized("accent.followSystem")).font(.app(12)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.name)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(option == choice ? .isSelected : [])
    }
}

// MARK: - Liquid Glass (macOS 26) with material fallback (macOS 14–15)

extension View {
    /// Functional-layer surface: Liquid Glass on macOS 26, `.regularMaterial` before. Never for list content.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        #else
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }

    /// `.glassProminent` / `.glass` on macOS 26, `.borderedProminent` / `.bordered` before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            // Only the primary action carries the accent; plain glass stays neutral (HIG: colour the key action only)
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass).tint(nil) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
        #else
        if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        #endif
    }

    /// Groups neighbouring glass so it blends (macOS 26); a plain container before.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 8) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
