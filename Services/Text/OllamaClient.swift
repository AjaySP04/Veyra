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

    func urlRequest(for request: ChatRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: "api/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = request.timeout / .seconds(1)
        urlRequest.httpBody = try JSONEncoder().encode(ChatBody(request))
        return urlRequest
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
    let keepAlive = "30m"
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
