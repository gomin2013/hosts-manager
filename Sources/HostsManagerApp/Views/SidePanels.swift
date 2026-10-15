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

/// Chat with the configured AI provider about this Mac's hosts file (ported from git-exclude-manager).
/// The AI never edits the file — it only answers; changes go through the editor (ADR-009).
struct ChatPanel: View {
    /// Current file text, sent as context with each question.
    let hostsText: String
    @Binding var isCollapsed: Bool

    @State private var turns: [ChatTurn] = []
    @State private var input = ""
    @State private var isAsking = false
    @State private var chatError: String?
    /// Cached so the body doesn't hit the Keychain on every render; reloaded when the settings sheet closes.
    @State private var aiSettings = AISettings.load()
    @State private var models: [String] = []
    @State private var showingSettings = false

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
        .sheet(isPresented: $showingSettings, onDismiss: reloadSettings) {
            AISettingsView { showingSettings = false }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                CollapseToggle(title: localized("chat.title"), isCollapsed: $isCollapsed)
                modelMenu
                    .padding(.leading, 16)  // align under the title, past the chevron
            }
            Spacer()
            Button(action: { showingSettings = true }, label: { Image(systemName: "gearshape") })
                .buttonStyle(.borderless)
                .help(localized("settings.title"))
                .accessibilityLabel(localized("settings.title"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .task(id: aiSettings.provider.rawValue + aiSettings.apiKey) { await loadModels() }
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("chat.welcome"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .center)

                ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                    bubble(turn)
                }
                if isAsking {
                    ProgressView().controlSize(.small).padding(.leading, 6)
                }
                if let chatError {
                    Text(chatError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                if !aiSettings.isConfigured {
                    Button(localized("chat.noApiKey")) { showingSettings = true }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(10)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: .infinity)
    }

    private func bubble(_ turn: ChatTurn) -> some View {
        let isUser = turn.role == .user
        return Text(turn.text)
            .font(.callout)
            .textSelection(.enabled)
            .padding(8)
            .background(isUser ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.15))
            .foregroundStyle(isUser ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    /// One-tap example prompts above the input.
    private var quickMessages: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            ForEach(Self.quickMessageKeys, id: \.self) { key in
                Button(action: {
                    input = localized(key)
                    send()
                }, label: {
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
                .disabled(isAsking || !aiSettings.isConfigured)
                .opacity(isAsking || !aiSettings.isConfigured ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField(localized("chat.placeholder"), text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
                .accessibilityLabel(localized("chat.placeholder"))

            Button(localized("btn.send"), action: send)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isAsking || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
    }

    /// Current model under the "AI Agent" title; click to switch models of the same provider.
    private var modelMenu: some View {
        Menu {
            if aiSettings.provider.needsModel {
                ForEach(models, id: \.self) { model in
                    Button(action: { selectModel(model) }, label: {
                        if model == aiSettings.model {
                            Label(model, systemImage: "checkmark")
                        } else {
                            Text(model)
                        }
                    })
                }
                if models.isEmpty {
                    Text(localized("settings.noModels"))
                }
                Divider()
            }
            Button(localized("settings.title") + "…") { showingSettings = true }
        } label: {
            Text(modelLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(aiSettings.isConfigured ? Color.primary : Color.orange)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(aiSettings.provider.displayName)
    }

    private var modelLabel: String {
        guard aiSettings.isConfigured else { return localized("ai.notConfigured") }
        return aiSettings.provider.needsModel ? aiSettings.model : aiSettings.provider.displayName
    }

    /// Gives the model this Mac's hosts file so answers are about *these* entries.
    static func systemPrompt(hostsFile: String, language: LanguageService.Language) -> String {
        """
        You are the assistant inside Hosts Manager, a macOS app that edits /etc/hosts. Each line is \
        "<ip> <hostname> [<hostname>…] [# comment]"; a line starting with "#" is a comment, and a commented-out \
        entry is disabled. A blank line followed by "# heading" starts a section. localhost and broadcasthost \
        are system entries that must not change. Help the user understand, fix and organize their entries. \
        You cannot edit the file — tell the user exactly which lines to add or change. Be concise. \
        Reply in \(language == .thai ? "Thai" : "English").

        Current /etc/hosts:
        \(hostsFile.isEmpty ? "(empty)" : hostsFile)
        """
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }
        turns.append(ChatTurn(role: .user, text: question))
        input = ""
        chatError = nil
        isAsking = true
        let history = turns, settings = aiSettings
        let system = Self.systemPrompt(hostsFile: hostsText, language: LanguageService.shared.current)
        Task {
            do {
                let reply = try await AIService.complete(settings, system: system, turns: history)
                turns.append(ChatTurn(role: .assistant, text: reply))
            } catch {
                chatError = error.localizedDescription
            }
            isAsking = false
        }
    }

    private func loadModels() async {
        let settings = aiSettings
        guard settings.provider.needsModel, !settings.provider.needsAPIKey || !settings.apiKey.isEmpty else {
            models = []
            return
        }
        models = (try? await AIService.listModels(settings.provider, apiKey: settings.apiKey)) ?? []
    }

    private func selectModel(_ model: String) {
        aiSettings.model = model
        aiSettings.save()
    }

    private func reloadSettings() {
        aiSettings = AISettings.load()
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
