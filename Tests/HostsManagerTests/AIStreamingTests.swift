import XCTest
import Shared
@testable import HostsManagerApp

/// Streaming request shapes and per-provider line parsing — no real network.
final class AIStreamingTests: XCTestCase {
    private let turns = [ChatTurn(role: .user, text: "hi")]

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func request(_ provider: AIProvider, model: String) throws -> URLRequest {
        let settings = AISettings(provider: provider, model: model, apiKey: "k")
        return try AIService.streamRequest(settings, system: "s", turns: turns)
    }

    // MARK: - Requests

    func testClaudeStreamsWithSummarizedAdaptiveThinking() throws {
        let json = try body(request(.claude, model: "claude-opus-5-5"))
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["max_tokens"] as? Int, 64000)
        XCTAssertEqual(json["thinking"] as? [String: String], ["type": "adaptive", "display": "summarized"])
        XCTAssertEqual(json["fallbacks"] as? String, "default")  // chatRequest's refusal fallback kept
    }

    func testOlderClaudeModelsGetNoThinkingConfig() throws {
        XCTAssertNil(try body(request(.claude, model: "claude-haiku-4-5"))["thinking"])
        XCTAssertTrue(AIService.claudeThinksAdaptively("claude-sonnet-5-5"))
        XCTAssertFalse(AIService.claudeThinksAdaptively("claude-opus-4-5"))
    }

    func testOllamaStreamsAndThinks() throws {
        let json = try body(request(.ollama, model: "qwen3"))
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["think"] as? Bool, true)
        let settings = AISettings(provider: .ollama, model: "llama3", apiKey: "")
        let retry = try body(AIService.streamRequest(settings, system: "s", turns: turns, think: false))
        XCTAssertEqual(retry["think"] as? Bool, false)
    }

    func testGeminiUsesSSEEndpointAndThoughtsOnlyFrom25() throws {
        let thinking = try request(.gemini, model: "gemini-2.5-pro")
        XCTAssertEqual(thinking.url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:streamGenerateContent?alt=sse")
        XCTAssertNotNil(try body(thinking)["generationConfig"])
        XCTAssertNil(try body(request(.gemini, model: "gemini-2.0-flash"))["generationConfig"])
    }

    func testOpenAIStreams() throws {
        XCTAssertEqual(try body(request(.openAI, model: "gpt-x"))["stream"] as? Bool, true)
    }

    // MARK: - Parsing

    func testClaudeDeltas() throws {
        let delta = #"data: {"type":"content_block_delta","index":0,"delta":"#
        let thinking = delta + #"{"type":"thinking_delta","thinking":"Hmm"}}"#
        let text = delta + #"{"type":"text_delta","text":"Hi"}}"#
        let signature = delta + #"{"type":"signature_delta","signature":"x"}}"#
        XCTAssertEqual(try AIService.parseStreamLine(.claude, thinking), [.thinking("Hmm")])
        XCTAssertEqual(try AIService.parseStreamLine(.claude, text), [.text("Hi")])
        XCTAssertEqual(try AIService.parseStreamLine(.claude, signature), [])
        XCTAssertEqual(try AIService.parseStreamLine(.claude, "event: content_block_delta"), [])
    }

    func testClaudeRefusalAndErrorEventThrow() {
        let refusal = #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#
        XCTAssertThrowsError(try AIService.parseStreamLine(.claude, refusal)) {
            XCTAssertEqual($0 as? AIError, .refused)
        }
        let error = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        XCTAssertThrowsError(try AIService.parseStreamLine(.claude, error)) {
            XCTAssertEqual($0 as? AIError, .unavailable("Overloaded"))
        }
    }

    func testOllamaLines() throws {
        let line = #"{"message":{"role":"assistant","content":"","thinking":"step 1"},"done":false}"#
        XCTAssertEqual(try AIService.parseStreamLine(.ollama, line), [.thinking("step 1")])
        let answer = #"{"message":{"role":"assistant","content":"127.0.0.1"},"done":false}"#
        XCTAssertEqual(try AIService.parseStreamLine(.ollama, answer), [.text("127.0.0.1")])
        XCTAssertThrowsError(try AIService.parseStreamLine(.ollama, #"{"error":"model not found"}"#))
    }

    func testOpenAILinesAndDone() throws {
        let line = #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#
        XCTAssertEqual(try AIService.parseStreamLine(.openAI, line), [.text("Hi")])
        let reasoning = #"data: {"choices":[{"delta":{"reasoning_content":"why"}}]}"#
        XCTAssertEqual(try AIService.parseStreamLine(.openAI, reasoning), [.thinking("why")])
        XCTAssertEqual(try AIService.parseStreamLine(.openAI, "data: [DONE]"), [])
    }

    /// Opt-in: the panel's streaming path against a real local Ollama — thinking first, then the answer.
    /// `LIVE_OLLAMA_MODEL=qwen3.8:latest swift test --filter testLiveOllamaStreams`
    @MainActor
    func testLiveOllamaStreams() async throws {
        guard let model = ProcessInfo.processInfo.environment["LIVE_OLLAMA_MODEL"] else {
            throw XCTSkip("set LIVE_OLLAMA_MODEL to run against a local Ollama")
        }
        let settings = AISettings(provider: .ollama, model: model, apiKey: "")
        let system = ChatPanel.systemPrompt(hostsFile: HostsLine.serialize(MockData.lines), language: .english)
        let question = ChatTurn(role: .user, text: "Which enabled hostnames point to 127.0.0.1? Names only.")
        var thinking = "", text = "", chunks = 0
        for try await event in AIService.stream(settings, system: system, turns: [question]) {
            chunks += 1
            switch event {
            case .thinking(let chunk): thinking += chunk
            case .text(let chunk): text += chunk
            }
        }
        print("chunks: \(chunks) · thinking: \(thinking.count) chars · answer: \(text)")
        XCTAssertGreaterThan(chunks, 1, "arrived in one piece — not streaming")
        XCTAssertTrue(text.contains("api.test"), text)
    }

    func testGeminiThoughtParts() throws {
        let line = #"data: {"candidates":[{"content":{"parts":[{"text":"plan","thought":true},{"text":"Answer"}]}}]}"#
        XCTAssertEqual(try AIService.parseStreamLine(.gemini, line), [.thinking("plan"), .text("Answer")])
    }

    /// qwen3 on Ollama: the tail of its thinking and a stray </think> arrive as answer text, the tag split across chunks.
    func testLeakedThinkingMovesOutOfTheAnswer() {
        var turn = ChatTurn(role: .assistant, text: "", thinking: "native")
        for chunk in ["0.0.0.0 ads.test\n</th", "ink>\n\nAdd this ", "line."] { turn.appendText(chunk) }
        XCTAssertEqual(turn.text, "Add this line.")
        XCTAssertEqual(turn.thinking, "native\n\n0.0.0.0 ads.test")

        var tagged = ChatTurn(role: .assistant, text: "")
        tagged.appendText("<think>plan</think>Answer")
        XCTAssertEqual(tagged.text, "Answer")
        XCTAssertEqual(tagged.thinking, "plan")
    }
}
