import Foundation

struct ChatRequest: Equatable {
    let model: String
    let system: String
    let user: String
    let timeout: Duration
}

protocol ChatCompleting {
    func complete(_ request: ChatRequest) async throws -> String
    func warmUp(_ model: String)
}

enum ChatError: Error, Equatable {
    case badStatus(Int)
    case malformedResponse
}
