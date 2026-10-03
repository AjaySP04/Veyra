enum SendKey {
    /// The key that sends the open message: Return in chats, ⌘⇧D in Mail, ⌘Return in other email apps and webmail.
    static func `for`(mode: DictationMode, bundleIdentifier: String?) -> KeyChord? {
        switch mode {
        case .chat: .returnKey
        case .email: bundleIdentifier == "com.apple.mail" ? .sendMail : .commandReturn
        case .standard, .editor, .terminal: nil
        }
    }
}
