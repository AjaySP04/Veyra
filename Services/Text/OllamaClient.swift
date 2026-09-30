import Foundation

struct OllamaClient: ChatCompleting {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func complete(_ request: ChatRequest) async throws -> String {
        let (data, response) = try await session.data(for: urlRequest(for: request))
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ChatError.malformedResponse }
        guard (200..<300).contains(status) else { throw ChatError.badStatus(status) }
        guard let reply = try? JSONDecoder().decode(ChatReply.self, from: data) else { throw ChatError.malformedResponse }
        return reply.message.content
    }

    func warmUp(_ model: String) {
        guard let request = try? warmUpRequest(for: model) else { return }
        Task { [session] in _ = try? await session.data(for: request) }
    }

    func urlRequest(for request: ChatRequest) throws -> URLRequest {
        try post("api/chat", body: ChatBody(request), timeout: request.timeout)
    }

    func warmUpRequest(for model: String) throws -> URLRequest {
        try post("api/generate", body: WarmUpBody(model: model), timeout: .seconds(300))
    }

    private func post(_ path: String, body: some Encodable, timeout: Duration) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: path))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = timeout / .seconds(1)
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }
}

private nonisolated struct WarmUpBody: Encodable {
    let model: String
    let keepAlive = ChatBody.keepAlive

    enum CodingKeys: String, CodingKey {
        case model
        case keepAlive = "keep_alive"
    }
}

private nonisolated struct ChatBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Options: Encodable {
        let temperature: Double
    }

    let model: String
    let messages: [Message]
    let stream = false
    let think = false
    static let keepAlive = "30m"

    let keepAlive = Self.keepAlive
    let options = Options(temperature: 0)

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, think, options
        case keepAlive = "keep_alive"
    }

    init(_ request: ChatRequest) {
        model = request.model
        messages = [
            Message(role: "system", content: request.system),
            Message(role: "user", content: request.user),
        ]
    }
}

private nonisolated struct ChatReply: Decodable {
    struct Message: Decodable {
        let content: String
    }

    let message: Message
}
