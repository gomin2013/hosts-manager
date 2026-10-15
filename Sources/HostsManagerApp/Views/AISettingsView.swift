import SwiftUI

/// AI API Settings sheet (⚙ in the AI Agent panel) — provider + model + API key, same as git-exclude-manager.
struct AISettingsView: View {
    var onDismiss: () -> Void = {}

    @State private var settings = AISettings.load()
    @State private var models: [String] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("settings.title")).font(.headline)

            Picker(localized("settings.provider"), selection: providerBinding) {
                ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
            }

            if settings.provider.needsAPIKey {
                SecureField(localized("settings.apiKey"), text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            if settings.provider.needsModel {
                HStack {
                    if models.isEmpty {
                        Button(localized("settings.loadModels"), action: loadModels)
                            .disabled(isLoadingModels || (settings.provider.needsAPIKey && settings.apiKey.isEmpty))
                    } else {
                        Menu(localized("settings.model")) {
                            ForEach(models, id: \.self) { model in
                                Button(model) { settings.model = model }
                            }
                        }
                        .fixedSize()
                    }
                    if isLoadingModels { ProgressView().controlSize(.small) }
                    TextField(localized("settings.model"), text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                Text(localized("settings.appleNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let modelError {
                Text(modelError).font(.caption).foregroundStyle(.red)
            }
            if settings.provider.needsAPIKey {
                Text(localized("settings.keychainNote")).font(.caption).foregroundStyle(.secondary)
                // ADR-009: the hosts file (internal hostnames / IPs) goes to this provider when you ask.
                Label(localized("settings.privacyNote"), systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(localized("btn.cancel"), action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button(localized("btn.save")) {
                    settings.save()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!settings.isConfigured)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    /// Switching provider loads that provider's saved model/key instead of carrying the old ones over.
    private var providerBinding: Binding<AIProvider> {
        Binding(
            get: { settings.provider },
            set: { provider in
                settings = AISettings.load(provider: provider)
                models = []
                modelError = nil
            }
        )
    }

    private func loadModels() {
        isLoadingModels = true
        modelError = nil
        let provider = settings.provider, apiKey = settings.apiKey
        Task {
            do {
                models = try await AIService.listModels(provider, apiKey: apiKey)
                if models.isEmpty { modelError = localized("settings.noModels") }
            } catch {
                modelError = error.localizedDescription
            }
            isLoadingModels = false
        }
    }
}
