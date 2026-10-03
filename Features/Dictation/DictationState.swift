enum DictationState: Equatable {
    case preparing(progress: Double?)
    case idle
    case recording(level: Float)
    case transcribing
    case acting
    case acted(message: String)
    /// A drafted message waits for "send it".
    case awaiting(message: String)
    case failed(message: String)
    case unavailable(message: String)
}
