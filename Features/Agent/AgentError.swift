enum AgentError: Error, Equatable {
    case unsupported
    case invalidArguments
    case unavailable
    case noApp(String)
    case noFile(String)
    case badAddress

    var message: String {
        switch self {
        case .unsupported: "I can only open apps, websites, folders and files for now"
        case .invalidArguments: "Didn't catch what to open"
        case .unavailable: "Actions need Ollama running"
        case .noApp(let target): "No app called “\(target)”"
        case .noFile(let target): "No file matching “\(target)”"
        case .badAddress: "Can't open that address"
        }
    }
}
