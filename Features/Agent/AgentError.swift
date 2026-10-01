enum AgentError: Error, Equatable {
    case unsupported
    case invalidArguments
    case unavailable
    case noApp(String)
    case noFile(String)
    case badAddress
    case noSelection
    case tooLong
    case rewriteFailed
    case appChanged

    var message: String {
        switch self {
        case .unsupported: "I can open things and rewrite text for now"
        case .invalidArguments: "Didn't catch what to do"
        case .unavailable: "Actions need Ollama running"
        case .noApp(let target): "No app called “\(target)”"
        case .noFile(let target): "No file matching “\(target)”"
        case .badAddress: "Can't open that address"
        case .noSelection: "Select some text first"
        case .tooLong: "That's too much text to rewrite"
        case .rewriteFailed: "Couldn't rewrite that"
        case .appChanged: "Cancelled because the app changed"
        }
    }
}
