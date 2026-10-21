import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI backends the user can pick in AI API Settings.
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case apple, ollama, openAI, gemini, claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple Foundation Models"
        case .ollama: return "Ollama (local)"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        }
    }

    var needsAPIKey: Bool { self == .openAI || self == .gemini || self == .claude }
    /// Apple has one on-device model; every other provider needs a model name.
    var needsModel: Bool { self != .apple }
}

struct ChatTurn: Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    var text: String
    /// Assistant only: reasoning the provider streamed (display only — never sent back).
    var thinking = ""
    /// Assistant only: how long the reply took, once it finished.
    var seconds: Int?

    /// Appends streamed answer text. Reasoning models sometimes put thinking in the answer itself — all of it inside
    /// `<think>…</think>` (no native thinking) or just its tail and a stray `</think>` (qwen3 on Ollama) — so whatever
    /// comes before a `</think>` moves to `thinking`.
    mutating func appendText(_ chunk: String) {
        text += chunk
        guard let end = text.range(of: "</think>") else { return }
        let leaked = text[..<end.lowerBound].replacing("<think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !leaked.isEmpty { thinking += (thinking.isEmpty ? "" : "\n\n") + leaked }
        text = String(text[end.upperBound...].drop(while: \.isWhitespace))
    }
}

enum AIError: LocalizedError, Equatable {
    case notConfigured
    case unavailable(String)
    case http(Int, String)
    case badResponse
    case refused

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI is not configured. Open Settings → AI API Settings."
        case .unavailable(let reason): return reason
        case .http(let status, let body): return "AI request failed (HTTP \(status)): \(body)"
        case .badResponse: return "Unexpected response from the AI provider."
        case .refused: return "The model declined this request."
        }
    }
}

/// User's AI choice. Provider + model live in UserDefaults; API keys live in the Keychain.
struct AISettings: Equatable, Sendable {
    var provider: AIProvider
    var model: String
    var apiKey: String

    private static let providerKey = "ai.provider"
    private static func modelKey(_ provider: AIProvider) -> String { "ai.model.\(provider.rawValue)" }

    static func load(_ defaults: UserDefaults = .standard) -> AISettings {
        let provider = defaults.string(forKey: providerKey).flatMap(AIProvider.init) ?? .apple
        return load(provider: provider, defaults)
    }

    static func load(provider: AIProvider, _ defaults: UserDefaults = .standard) -> AISettings {
        AISettings(
            provider: provider,
            model: defaults.string(forKey: modelKey(provider)) ?? (provider == .claude ? "claude-opus-5-5" : ""),
            apiKey: provider.needsAPIKey ? Keychain.read(account: provider.rawValue) ?? "" : ""
        )
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: Self.providerKey)
        defaults.set(model, forKey: Self.modelKey(provider))
        if provider.needsAPIKey { Keychain.save(apiKey, account: provider.rawValue) }
    }

    var isConfigured: Bool {
        if provider == .apple { return AIService.isAppleModelAvailable }
        return (!provider.needsModel || !model.isEmpty) && (!provider.needsAPIKey || !apiKey.isEmpty)
    }
}

/// Minimal generic-password Keychain wrapper (one item per provider).
enum Keychain {
    private static let service = "com.hostsmanager.ai"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// One entry point for every provider: `complete` for replies, `listModels` for the settings picker.
enum AIService {
    static func complete(_ settings: AISettings, system: String, turns: [ChatTurn]) async throws -> String {
        guard settings.isConfigured else { throw AIError.notConfigured }
        if settings.provider == .apple {
            return try await appleComplete(system: system, turns: turns)
        }
        let request = try chatRequest(settings, system: system, turns: turns)
        return try parseReply(settings.provider, data: try await send(request))
    }

    static func listModels(_ provider: AIProvider, apiKey: String) async throws -> [String] {
        guard let request = modelsRequest(provider, apiKey: apiKey) else { return [] }
        return curatedModels(provider, try parseModels(provider, data: try await send(request)))
    }

    /// Cloud lists run to dozens of IDs (previews, TTS, image, dated snapshots), so the pickers keep only the newest
    /// model of each cheap-but-good family; the first family is the one marked "(Recommended)". Ollama is left alone —
    /// it lists only what the user pulled.
    static let modelFamilies: [AIProvider: [String]] = [
        .openAI: [#"^gpt-[\d.]+-mini$"#, #"^gpt-[\d.]+-nano$"#],
        .gemini: [#"^gemini-[\d.]+-flash-lite$"#, #"^gemini-[\d.]+-flash$"#],
        .claude: [#"^claude-haiku-\d+(-\d+)?(-\d{8})?$"#, #"^claude-sonnet-\d+(-\d+)?(-\d{8})?$"#]
    ]

    static func curatedModels(_ provider: AIProvider, _ ids: [String]) -> [String] {
        guard let families = modelFamilies[provider] else { return ids.sorted() }
        let picks = families.compactMap { pattern in
            ids.filter { $0.range(of: pattern, options: .regularExpression) != nil }
                .max { $0.compare($1, options: .numeric) == .orderedAscending }
        }
        // ponytail: naming scheme changed and nothing matched — show everything rather than an empty picker
        return picks.isEmpty ? ids.sorted() : picks
    }

    @MainActor
    static func modelLabel(_ model: String, provider: AIProvider) -> String {
        guard let first = modelFamilies[provider]?.first,
              model.range(of: first, options: .regularExpression) != nil else { return model }
        return "\(model) (\(localized("settings.recommended")))"
    }

    // MARK: - Request building (pure, unit-tested)

    static func chatRequest(_ settings: AISettings, system: String, turns: [ChatTurn]) throws -> URLRequest {
        let messages = turns.map { ["role": $0.role.rawValue, "content": $0.text] }
        var request: URLRequest
        var body: [String: Any]

        switch settings.provider {
        case .apple:
            throw AIError.unavailable("Apple Foundation Models runs on-device, not over HTTP.")
        case .ollama:
            request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
            // think:false — local thinking models (qwen3 etc.) otherwise reason for minutes on CPU-offloaded
            // hardware; measured 4+ min → 3.5 s for a one-line comment. Our prompts don't need reasoning.
            body = ["model": settings.model, "stream": false, "think": false,
                    "messages": [["role": "system", "content": system]] + messages]
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
            body = ["model": settings.model,
                    "messages": [["role": "system", "content": system]] + messages]
        case .gemini:
            let model = settings.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? settings.model
            request = URLRequest(url: URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
            request.setValue(settings.apiKey, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": turns.map {
                    ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]]
                }
            ]
        case .claude:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": settings.model, "max_tokens": 16000, "system": system, "messages": messages]
            // Server-side refusal fallback; only these models accept the "default" form (others 400).
            if claudeFallbackModels.contains(settings.model) {
                request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                body["fallbacks"] = "default"
            }
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300  // reasoning models can take minutes
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static let claudeFallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"
    ]

    static func modelsRequest(_ provider: AIProvider, apiKey: String) -> URLRequest? {
        var request: URLRequest
        switch provider {
        case .apple:
            return nil
        case .ollama:
            request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .claude:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1000")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.timeoutInterval = 15
        return request
    }

    // MARK: - Response parsing (pure, unit-tested)

    static func parseReply(_ provider: AIProvider, data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }
        let text: String?
        switch provider {
        case .apple:
            text = nil
        case .ollama:
            text = (json["message"] as? [String: Any])?["content"] as? String
        case .openAI:
            let choices = json["choices"] as? [[String: Any]]
            text = (choices?.first?["message"] as? [String: Any])?["content"] as? String
        case .gemini:
            let candidates = json["candidates"] as? [[String: Any]]
            let parts = (candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
            text = parts?.compactMap { $0["text"] as? String }.joined()
        case .claude:
            // Check refusal before reading content (content may be empty or partial).
            if json["stop_reason"] as? String == "refusal" { throw AIError.refused }
            let blocks = json["content"] as? [[String: Any]]
            text = blocks?.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined()
        }
        guard let text, !text.isEmpty else { throw AIError.badResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseModels(_ provider: AIProvider, data: Data) throws -> [String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }
        switch provider {
        case .apple:
            return []
        case .ollama:
            return (json["models"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        case .openAI, .claude:
            return (json["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        case .gemini:
            return (json["models"] as? [[String: Any]])?
                .filter { ($0["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true }
                .compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") } ?? []
        }
    }

    // MARK: - Transport

    private static func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if request.url?.host == "127.0.0.1" {
                throw AIError.unavailable("Cannot reach Ollama at 127.0.0.1:11434. Is `ollama serve` running?")
            }
            throw error
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(http.statusCode, String(bytes: data.prefix(300), encoding: .utf8) ?? "")
        }
        return data
    }

    /// False below macOS 26 or when Apple Intelligence is off — the UI then asks the user to configure AI.
    static var isAppleModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    private static func appleComplete(system: String, turns: [ChatTurn]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw AIError.unavailable("Apple Intelligence is not available or not enabled on this Mac.")
            }
            let session = LanguageModelSession(instructions: system)
            return try await session.respond(to: foldedPrompt(turns)).content
        }
        #endif
        throw AIError.unavailable("Apple Foundation Models needs macOS 26 or later.")
    }

    // ponytail: history folded into one prompt; keep a LanguageModelSession per chat if context matters
    static func foldedPrompt(_ turns: [ChatTurn]) -> String {
        turns.map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n\n")
    }
}
