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
}
