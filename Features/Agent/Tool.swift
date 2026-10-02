enum ToolRisk {
    case immediate
}

struct ToolContext: Equatable {
    let mode: DictationMode
    let bundleIdentifier: String?
    let lastInsertion: LastInsertion?
    /// False once the user has typed, clicked or turned on secure input since the action started.
    let isUntouched: () -> Bool

    init(mode: DictationMode, bundleIdentifier: String?, lastInsertion: LastInsertion?, isUntouched: @escaping () -> Bool = { true }) {
        self.mode = mode
        self.bundleIdentifier = bundleIdentifier
        self.lastInsertion = lastInsertion
        self.isUntouched = isUntouched
    }

    static let none = ToolContext(mode: .standard, bundleIdentifier: nil, lastInsertion: nil)

    static func == (lhs: ToolContext, rhs: ToolContext) -> Bool {
        lhs.mode == rhs.mode && lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.lastInsertion == rhs.lastInsertion
    }
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
