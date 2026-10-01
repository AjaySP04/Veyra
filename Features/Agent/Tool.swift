enum ToolRisk {
    case immediate
}

struct PreparedAction {
    let done: String
    let failure: String
    let perform: () async throws -> Void
}

protocol Tool {
    var definition: ToolDefinition { get }
    var risk: ToolRisk { get }
    func prepare(_ arguments: [String: String]) async throws -> PreparedAction
}
