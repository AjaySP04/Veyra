import Foundation

struct ChatRequest: Equatable {
    let model: String
    let system: String
    let user: String
    let timeout: Duration
}

protocol ChatCompleting {
    func complete(_ request: ChatRequest) async throws -> String
}

enum ChatError: Error, Equatable {
    case badStatus(Int)
    case malformedResponse
}
