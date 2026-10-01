import Foundation
import Testing
@testable import Veyra

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
@Suite(.serialized)
struct OllamaClientTests {
    private let request = ChatRequest(model: "gemma4:latest", system: "sys", user: "hello", timeout: .seconds(6))
    private let client: OllamaClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OllamaClient(session: URLSession(configuration: configuration))
    }()

    @Test func buildsChatRequest() throws {
        let urlRequest = try client.urlRequest(for: request)
        #expect(urlRequest.url?.absoluteString == "http://localhost:11434/api/chat")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(urlRequest.timeoutInterval == 6)

        let body = try #require(JSONSerialization.jsonObject(with: urlRequest.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "gemma4:latest")
        #expect(body["stream"] as? Bool == false)
        #expect(body["think"] as? Bool == false)
        #expect(body["keep_alive"] as? String == "30m")
        #expect((body["options"] as? [String: Any])?["temperature"] as? Double == 0)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "sys"], ["role": "user", "content": "hello"]])
    }

    @Test func buildsWarmUpRequest() throws {
        let urlRequest = try client.warmUpRequest(for: "gemma4:latest")
        #expect(urlRequest.url?.absoluteString == "http://localhost:11434/api/generate")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.timeoutInterval == 300)
        let body = try #require(JSONSerialization.jsonObject(with: urlRequest.httpBody ?? Data()) as? [String: String])
        #expect(body == ["model": "gemma4:latest", "keep_alive": "30m"])
    }

    @Test func returnsMessageContent() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"message":{"role":"assistant","content":"Hello."},"done":true}"#.utf8)
        #expect(try await client.complete(request) == "Hello.")
    }

    @Test func throwsOnErrorStatus() async {
        StubURLProtocol.status = 404
        StubURLProtocol.body = Data(#"{"error":"model not found"}"#.utf8)
        await #expect(throws: ChatError.badStatus(404)) { try await client.complete(request) }
    }

    @Test func throwsOnMalformedBody() async {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"done":true}"#.utf8)
        await #expect(throws: ChatError.malformedResponse) { try await client.complete(request) }
    }

    private let toolRequest = ToolRequest(
        model: "gemma4:latest", system: "sys", user: "open slack",
        tools: [ToolDefinition(name: "open", description: "Open things", parameters: [
            ToolParameter(name: "kind", description: "What", allowed: ["app", "file"]),
            ToolParameter(name: "target", description: "Name", allowed: nil),
        ])],
        timeout: .seconds(6)
    )

    @Test func buildsToolRequest() throws {
        let urlRequest = try client.urlRequest(for: toolRequest)
        #expect(urlRequest.url?.absoluteString == "http://localhost:11434/api/chat")
        let body = try #require(JSONSerialization.jsonObject(with: urlRequest.httpBody ?? Data()) as? [String: Any])
        #expect(body["think"] as? Bool == false)
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "function")
        let function = try #require(tools[0]["function"] as? [String: Any])
        #expect(function["name"] as? String == "open")
        #expect(function["description"] as? String == "Open things")
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
        #expect(parameters["required"] as? [String] == ["kind", "target"])
        let properties = try #require(parameters["properties"] as? [String: [String: Any]])
        #expect(properties["kind"]?["type"] as? String == "string")
        #expect(properties["kind"]?["enum"] as? [String] == ["app", "file"])
        #expect(properties["target"]?["enum"] == nil)
        #expect(properties["target"]?["description"] as? String == "Name")
    }

    @Test func chatRequestHasNoTools() throws {
        let body = try #require(JSONSerialization.jsonObject(with: client.urlRequest(for: request).httpBody ?? Data()) as? [String: Any])
        #expect(body["tools"] == nil)
    }

    @Test func decodesToolCall() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"open","arguments":{"kind":"app","target":"Slack"}}}]},"done":true}"#.utf8)
        #expect(try await client.callTool(toolRequest) == .call(ToolCall(name: "open", arguments: ["kind": "app", "target": "Slack"])))
    }

    @Test func decodesTextReply() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"message":{"role":"assistant","content":"unsupported"},"done":true}"#.utf8)
        #expect(try await client.callTool(toolRequest) == .text("unsupported"))
    }

    @Test func toolCallThrowsOnErrorStatus() async {
        StubURLProtocol.status = 500
        StubURLProtocol.body = Data()
        await #expect(throws: ChatError.badStatus(500)) { try await client.callTool(toolRequest) }
    }

    @Test func nonStringArgumentsAreKeptAsTextOrDropped() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"open","arguments":{"kind":"file","target":2024,"exact":true,"extra":null,"list":["a"]}}}]},"done":true}"#.utf8)
        #expect(try await client.callTool(toolRequest) == .call(ToolCall(name: "open", arguments: ["kind": "file", "target": "2024", "exact": "true"])))
    }
}
