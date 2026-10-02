enum DictationState: Equatable {
    case preparing(progress: Double?)
    case idle
    case recording(level: Float)
    case transcribing
    case acting
    case acted(message: String)
    case failed(message: String)
    case unavailable(message: String)
}
