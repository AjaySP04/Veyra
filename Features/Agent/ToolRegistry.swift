struct ToolRegistry {
    private let tools: [any Tool]

    init(_ tools: [any Tool]) {
        self.tools = tools
    }

    var definitions: [ToolDefinition] { tools.map(\.definition) }

    func tool(named name: String) -> (any Tool)? {
        tools.first { $0.definition.name == name }
    }
}
