enum Intent: Equatable {
    case dictate(String)
    case command(VoiceCommand)

    init(_ transcript: String) {
        self = VoiceCommand(phrase: transcript).map(Intent.command) ?? .dictate(transcript)
    }
}
