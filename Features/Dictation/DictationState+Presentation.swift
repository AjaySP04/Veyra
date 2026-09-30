extension DictationState {
    var menuBarSymbol: String {
        switch self {
        case .preparing, .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        case .failed, .unavailable: "exclamationmark.triangle"
        }
    }

    var statusText: String {
        switch self {
        case .preparing(let progress?) where progress < 1: "Downloading speech model… \(Int(progress * 100))%"
        case .preparing: "Loading speech model…"
        case .idle: "Hold Fn to dictate"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .failed(let message), .unavailable(let message): message
        }
    }

    var showsOverlay: Bool {
        switch self {
        case .recording, .transcribing, .failed: true
        case .preparing, .idle, .unavailable: false
        }
    }
}
