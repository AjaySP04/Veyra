enum ToolRisk {
    /// Local and undoable: performed straight away.
    case immediate
    /// Leaves the Mac or can't be undone: `perform` only prepares it (a draft), and the `confirmation` runs after the user says so.
    case confirm
}

/// The step a `.confirm` tool holds back until the user confirms, such as pressing a chat's send key.
struct Confirmation: Equatable {
    let done: String
    let failure: String
    let perform: () async throws -> Void

    static func == (lhs: Confirmation, rhs: Confirmation) -> Bool {
        lhs.done == rhs.done && lhs.failure == rhs.failure
    }
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
    var confirmation: Confirmation? = nil
    let perform: () async throws -> Void
}

protocol Tool {
    var definition: ToolDefinition { get }
    var risk: ToolRisk { get }
    func prepare(_ arguments: [String: String], in context: ToolContext) async throws -> PreparedAction
}
