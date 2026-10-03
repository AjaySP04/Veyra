extension DictationState {
    var menuBarIcon: MenuBarIcon {
        switch self {
        case .preparing, .idle, .recording, .acted, .awaiting: .mark(swinging: false)
        case .transcribing, .acting: .mark(swinging: true)
        case .failed, .unavailable: .symbol("exclamationmark.triangle")
        }
    }

    var statusText: String {
        switch self {
        case .preparing(let progress?) where progress < 1: "Downloading speech model… \(Int(progress * 100))%"
        case .preparing: "Loading speech model…"
        case .idle: "Hold Fn to dictate"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .acting: "Working…"
        case .acted(let message), .awaiting(let message): message
        case .failed(let message), .unavailable(let message): message
        }
    }

    var showsOverlay: Bool {
        switch self {
        case .recording, .transcribing, .acting, .acted, .awaiting, .failed: true
        case .preparing, .idle, .unavailable: false
        }
    }
}
