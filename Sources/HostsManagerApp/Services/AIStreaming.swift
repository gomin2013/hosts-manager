import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One piece of a streamed reply: the model's visible reasoning, or answer text. Chunks arrive in order.
enum AIStreamEvent: Equatable, Sendable {
    case thinking(String)
    case text(String)
}

/// Streaming chat for the AI Agent panel: the user sees thinking and the answer as they arrive instead of a long
/// silent wait. Generate Comment keeps `complete` (one short line, no thinking).
extension AIService {
    static func stream(
        _ settings: AISettings, system: String, turns: [ChatTurn]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard settings.isConfigured else { throw AIError.notConfigured }
                    if settings.provider == .apple {
                        try await appleStream(system: system, turns: turns) { continuation.yield($0) }
                    } else {
                        try await httpStream(settings, system: system, turns: turns, think: true) {
                            continuation.yield($0)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building (pure, unit-tested)

    /// `chatRequest` + streaming and visible thinking where the provider and model support it.
    static func streamRequest(
        _ settings: AISettings, system: String, turns: [ChatTurn], think: Bool = true
    ) throws -> URLRequest {
        var request = try chatRequest(settings, system: system, turns: turns)
        var body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
        switch settings.provider {
        case .apple:
            break  // chatRequest already threw
        case .ollama:
            // Thinking on for chat (it streams, so a long think shows progress); thinking-less models get a retry
            body["stream"] = true
            body["think"] = think
        case .openAI:
            body["stream"] = true
        case .gemini:
            let url = request.url?.absoluteString.replacingOccurrences(
                of: ":generateContent", with: ":streamGenerateContent?alt=sse"
            )
            request.url = url.flatMap(URL.init(string:))
            if think && geminiThinks(settings.model) {
                body["generationConfig"] = ["thinkingConfig": ["includeThoughts": true]]
            }
        case .claude:
            body["stream"] = true
            body["max_tokens"] = 64000  // streaming: no HTTP-timeout reason to keep it low
            // Without "summarized" current models stream empty thinking blocks — a long pause before the answer
            if think && claudeThinksAdaptively(settings.model) {
                body["thinking"] = ["type": "adaptive", "display": "summarized"]
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Adaptive thinking exists from Opus/Sonnet 4.6 on; older models (Haiku 4.5, 4.5 and before) reject it.
    static func claudeThinksAdaptively(_ model: String) -> Bool {
        ["claude-fable-", "claude-mythos-", "claude-opus-5", "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8",
         "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-5"].contains { model.hasPrefix($0) }
    }

    /// Gemini returns thought summaries from 2.5 on; earlier models reject `thinkingConfig`.
    static func geminiThinks(_ model: String) -> Bool {
        model.hasPrefix("gemini-2.5") || model.hasPrefix("gemini-3")
    }

    // MARK: - Stream parsing (pure, unit-tested)

    /// One line of the response body: an SSE `data:` line (OpenAI, Gemini, Claude) or an NDJSON line (Ollama).
    /// `event:` lines, keep-alives and `[DONE]` carry nothing.
    static func parseStreamLine(_ provider: AIProvider, _ line: String) throws -> [AIStreamEvent] {
        var payload = line.trimmingCharacters(in: .whitespaces)
        if payload.hasPrefix("data:") { payload = payload.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        guard payload.hasPrefix("{"),
              let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            return []
        }
        // Mid-stream errors: Ollama sends a string, the others an object with a message
        if let message = json["error"] as? String ?? (json["error"] as? [String: Any])?["message"] as? String {
            throw AIError.unavailable(message)
        }
        switch provider {
        case .apple:
            return []
        case .ollama:
            let message = json["message"] as? [String: Any]
            return events(thinking: message?["thinking"], text: message?["content"])
        case .openAI:
            let delta = (json["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any]
            // OpenAI-compatible servers (vLLM, LM Studio) put reasoning in `reasoning_content`
            return events(thinking: delta?["reasoning_content"] ?? delta?["reasoning"], text: delta?["content"])
        case .gemini:
            let candidate = (json["candidates"] as? [[String: Any]])?.first
            let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            return parts.flatMap { part in
                part["thought"] as? Bool == true ? events(thinking: part["text"], text: nil)
                    : events(thinking: nil, text: part["text"])
            }
        case .claude:
            return try claudeEvents(json)
        }
    }

    private static func claudeEvents(_ json: [String: Any]) throws -> [AIStreamEvent] {
        switch json["type"] as? String {
        case "content_block_delta":
            let delta = json["delta"] as? [String: Any]
            switch delta?["type"] as? String {
            case "thinking_delta": return events(thinking: delta?["thinking"], text: nil)
            case "text_delta": return events(thinking: nil, text: delta?["text"])
            default: return []  // signature_delta, input_json_delta
            }
        case "message_delta":
            // Check refusal: the partial answer before it is not a complete reply
            if (json["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal" { throw AIError.refused }
            return []
        default:
            return []
        }
    }

    private static func events(thinking: Any?, text: Any?) -> [AIStreamEvent] {
        var result: [AIStreamEvent] = []
        if let thinking = thinking as? String, !thinking.isEmpty { result.append(.thinking(thinking)) }
        if let text = text as? String, !text.isEmpty { result.append(.text(text)) }
        return result
    }

    // MARK: - Transport

    private static func httpStream(
        _ settings: AISettings, system: String, turns: [ChatTurn], think: Bool,
        yield: (AIStreamEvent) -> Void
    ) async throws {
        let request = try streamRequest(settings, system: system, turns: turns, think: think)
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            if request.url?.host == "127.0.0.1" {
                throw AIError.unavailable("Cannot reach Ollama at 127.0.0.1:11434. Is `ollama serve` running?")
            }
            throw error
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines where body.count < 300 { body += line }
            // Ollama rejects think:true for models that can't think — ask again without it
            if think, settings.provider == .ollama, body.contains("does not support thinking") {
                return try await httpStream(settings, system: system, turns: turns, think: false, yield: yield)
            }
            throw AIError.http(http.statusCode, String(body.prefix(300)))
        }
        for try await line in bytes.lines {
            for event in try parseStreamLine(settings.provider, line) { yield(event) }
        }
    }

    private static func appleStream(
        system: String, turns: [ChatTurn], yield: (AIStreamEvent) -> Void
    ) async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw AIError.unavailable("Apple Intelligence is not available or not enabled on this Mac.")
            }
            let session = LanguageModelSession(instructions: system)
            var sent = ""
            // Snapshots are the whole answer so far; pass on only what's new
            for try await snapshot in session.streamResponse(to: foldedPrompt(turns)) {
                let content = snapshot.content
                if content.hasPrefix(sent) {
                    yield(.text(String(content.dropFirst(sent.count))))
                } else {
                    yield(.text(content))  // ponytail: a rewritten snapshot is appended, not replaced; rare
                }
                sent = content
            }
            return
        }
        #endif
        throw AIError.unavailable("Apple Foundation Models needs macOS 26 or later.")
    }
}
