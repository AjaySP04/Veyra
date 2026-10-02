import Foundation

struct ToolParameter: Equatable {
    let name: String
    let description: String
    let allowed: [String]?
}

struct ToolDefinition: Equatable {
    let name: String
    let description: String
    let parameters: [ToolParameter]
}

struct ToolRequest: Equatable {
    let model: String
    let system: String
    let user: String
    let tools: [ToolDefinition]
    let timeout: Duration
}

struct ToolCall: Equatable {
    let name: String
    let arguments: [String: String]
}

enum ToolReply: Equatable {
    case call(ToolCall)
    case text(String)
}

protocol ToolCalling {
    func callTool(_ request: ToolRequest) async throws -> ToolReply
}
