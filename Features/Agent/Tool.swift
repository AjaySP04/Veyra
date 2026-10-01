enum ToolRisk {
    case immediate
}

struct ToolContext: Equatable {
    let mode: DictationMode
    let bundleIdentifier: String?
    let lastInsertion: LastInsertion?

    static let none = ToolContext(mode: .standard, bundleIdentifier: nil, lastInsertion: nil)
}

struct PreparedAction {
    let done: String
    let failure: String
    var insertion: LastInsertion? = nil
    let perform: () async throws -> Void
}

protocol Tool {
    var definition: ToolDefinition { get }
    var risk: ToolRisk { get }
    func prepare(_ arguments: [String: String], in context: ToolContext) async throws -> PreparedAction
}
