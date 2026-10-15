import XCTest
import Shared
@testable import HostsManagerApp

/// Answers every URLSession.shared request in-process (registered per test).
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (status: Int, body: String) = (200, "{}")
    nonisolated(unsafe) static var lastURL: URL?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lastURL = request.url
        let http = HTTPURLResponse(
            url: request.url!, statusCode: Self.response.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Request shapes and response parsing per provider — no real network.
final class AIServiceTests: XCTestCase {
    private let turns = [ChatTurn(role: .user, text: "hi")]

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    // MARK: - Requests

    func testClaudeRequestHeadersAndFallbackOnSupportedModel() throws {
        let settings = AISettings(provider: .claude, model: "claude-opus-5-5", apiKey: "k")
        let request = try AIService.chatRequest(settings, system: "sys", turns: turns)

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let json = try body(request)
        XCTAssertEqual(json["system"] as? String, "sys")
        XCTAssertEqual(json["fallbacks"] as? String, "default")
    }

    func testClaudeRequestOmitsFallbackOnHaiku() throws {
        let settings = AISettings(provider: .claude, model: "claude-haiku-5-5", apiKey: "k")
        let request = try AIService.chatRequest(settings, system: "sys", turns: turns)

        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"))
        XCTAssertNil(try body(request)["fallbacks"])
    }

    func testOpenAIAndOllamaPutSystemFirst() throws {
        for provider in [AIProvider.openAI, .ollama] {
            let settings = AISettings(provider: provider, model: "m", apiKey: "k")
            let messages = try body(AIService.chatRequest(settings, system: "sys", turns: turns))["messages"]
                as? [[String: String]]
            XCTAssertEqual(messages?.first, ["role": "system", "content": "sys"], provider.rawValue)
            XCTAssertEqual(messages?.last, ["role": "user", "content": "hi"], provider.rawValue)
        }
        let ollama = try body(AIService.chatRequest(
            AISettings(provider: .ollama, model: "m", apiKey: ""), system: "s", turns: turns))
        XCTAssertEqual(ollama["think"] as? Bool, false)
    }

    func testGeminiUsesModelRoleAndSystemInstruction() throws {
        let settings = AISettings(provider: .gemini, model: "gemini-x", apiKey: "k")
        let request = try AIService.chatRequest(
            settings, system: "sys", turns: [ChatTurn(role: .user, text: "q"), ChatTurn(role: .assistant, text: "a")]
        )

        XCTAssertTrue(request.url!.absoluteString.hasSuffix("/models/gemini-x:generateContent"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "k")
        let contents = try body(request)["contents"] as? [[String: Any]]
        XCTAssertEqual(contents?.map { $0["role"] as? String }, ["user", "model"])
    }

    // MARK: - Replies

    func testParseReplies() throws {
        let cases: [(AIProvider, String)] = [
            (.ollama, #"{"message":{"role":"assistant","content":" ok "}}"#),
            (.openAI, #"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#),
            (.gemini, #"{"candidates":[{"content":{"parts":[{"text":"o"},{"text":"k"}]}}]}"#),
            (.claude, #"{"stop_reason":"end_turn","content":"#
                + #"[{"type":"thinking","thinking":""},{"type":"text","text":"ok"}]}"#)
        ]
        for (provider, json) in cases {
            XCTAssertEqual(try AIService.parseReply(provider, data: Data(json.utf8)), "ok", provider.rawValue)
        }
    }

    func testClaudeRefusalThrows() {
        let json = #"{"stop_reason":"refusal","content":[]}"#
        XCTAssertThrowsError(try AIService.parseReply(.claude, data: Data(json.utf8))) {
            XCTAssertEqual($0 as? AIError, .refused)
        }
    }

    // MARK: - Model lists

    func testParseModels() throws {
        XCTAssertEqual(
            try AIService.parseModels(.ollama, data: Data(#"{"models":[{"name":"llama3.2:latest"}]}"#.utf8)),
            ["llama3.2:latest"]
        )
        XCTAssertEqual(
            try AIService.parseModels(
                .claude, data: Data(#"{"data":[{"id":"claude-opus-5-5"}],"has_more":false}"#.utf8)
            ),
            ["claude-opus-5-5"]
        )
        let gemini = #"""
        {"models":[
          {"name":"models/gemini-a","supportedGenerationMethods":["generateContent"]},
          {"name":"models/embed-b","supportedGenerationMethods":["embedContent"]}
        ]}
        """#
        XCTAssertEqual(try AIService.parseModels(.gemini, data: Data(gemini.utf8)), ["gemini-a"])
    }

    func testIsConfigured() {
        let apple = AISettings(provider: .apple, model: "", apiKey: "")
        XCTAssertEqual(apple.isConfigured, AIService.isAppleModelAvailable)
        XCTAssertFalse(AISettings(provider: .ollama, model: "", apiKey: "").isConfigured)
        XCTAssertFalse(AISettings(provider: .claude, model: "claude-opus-5-5", apiKey: "").isConfigured)
        XCTAssertTrue(AISettings(provider: .claude, model: "claude-opus-5-5", apiKey: "k").isConfigured)
    }

    // MARK: - Transport (stubbed URLSession)

    private func withStub<T>(_ status: Int, _ body: String, _ run: () async throws -> T) async rethrows -> T {
        StubURLProtocol.response = (status, body)
        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }
        return try await run()
    }

    func testCompleteSendsAndParses() async throws {
        let settings = AISettings(provider: .ollama, model: "m", apiKey: "")
        let reply = try await withStub(200, #"{"message":{"content":"hello"}}"#) {
            try await AIService.complete(settings, system: "s", turns: turns)
        }
        XCTAssertEqual(reply, "hello")
        XCTAssertEqual(StubURLProtocol.lastURL?.path, "/api/chat")
    }

    func testHTTPErrorCarriesStatusAndBody() async {
        let settings = AISettings(provider: .claude, model: "claude-opus-5-5", apiKey: "bad")
        do {
            _ = try await withStub(401, "invalid x-api-key") {
                try await AIService.complete(settings, system: "s", turns: turns)
            }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AIError, .http(401, "invalid x-api-key"))
        }
    }

    func testListModelsIsSortedAndAppleHasNone() async throws {
        let models = try await withStub(200, #"{"data":[{"id":"b"},{"id":"a"}]}"#) {
            try await AIService.listModels(.openAI, apiKey: "k")
        }
        XCTAssertEqual(models, ["a", "b"])
        let apple = try await AIService.listModels(.apple, apiKey: "")
        XCTAssertEqual(apple, [])
    }

    func testCompleteRequiresConfiguration() async {
        do {
            let unconfigured = AISettings(provider: .ollama, model: "", apiKey: "")
            _ = try await AIService.complete(unconfigured, system: "s", turns: turns)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AIError, .notConfigured)
        }
    }

    // MARK: - Settings persistence (Ollama: no Keychain involved)

    func testSettingsRoundTripThroughDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AIServiceTests-\(UUID().uuidString)"))
        AISettings(provider: .ollama, model: "qwen3.6:latest", apiKey: "").save(defaults)

        XCTAssertEqual(AISettings.load(defaults), AISettings(provider: .ollama, model: "qwen3.6:latest", apiKey: ""))
        XCTAssertEqual(AISettings.load(provider: .gemini, defaults).model, "")
    }

    // MARK: - Hosts system prompt (ADR-009)

    @MainActor
    func testSystemPromptCarriesHostsFileLanguageAndNoEditRule() {
        let prompt = ChatPanel.systemPrompt(hostsFile: "127.0.0.1\tapi.test\n", language: .thai)
        XCTAssertTrue(prompt.contains("Current /etc/hosts:\n127.0.0.1\tapi.test"))
        XCTAssertTrue(prompt.contains("Reply in Thai"))
        XCTAssertTrue(prompt.contains("You cannot edit the file"))
        XCTAssertTrue(ChatPanel.systemPrompt(hostsFile: "", language: .english).hasSuffix("(empty)"))
    }

    /// Opt-in smoke test against a real local Ollama — same code path and prompt as the AI Agent panel.
    /// `LIVE_OLLAMA_MODEL=qwen3.6:latest swift test --filter testLiveOllama`
    @MainActor
    func testLiveOllamaAnswersAboutTheHostsFile() async throws {
        guard let model = ProcessInfo.processInfo.environment["LIVE_OLLAMA_MODEL"] else {
            throw XCTSkip("set LIVE_OLLAMA_MODEL to run against a local Ollama")
        }
        let settings = AISettings(provider: .ollama, model: model, apiKey: "")
        let system = ChatPanel.systemPrompt(hostsFile: HostsLine.serialize(MockData.lines), language: .english)
        let question = ChatTurn(role: .user, text: "Which enabled hostnames point to 127.0.0.1? List the names only.")
        let reply = try await AIService.complete(settings, system: system, turns: [question])
        print("Ollama reply:", reply)
        XCTAssertTrue(reply.contains("api.test"), reply)
    }

    func testErrorsHaveMessages() {
        let errors: [AIError] = [.notConfigured, .unavailable("x"), .http(500, "y"), .badResponse, .refused]
        XCTAssertTrue(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }
}
