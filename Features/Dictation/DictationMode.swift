import Foundation

enum DictationMode: String, Equatable {
    case email, chat, editor, terminal, standard

    private static let appModes: [String: DictationMode] = [
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.readdle.SparkDesktop": .email,
        "com.readdle.smartemail-Mac": .email,
        "com.tinyspeck.slackmacgap": .chat,
        "com.microsoft.teams2": .chat,
        "com.microsoft.teams": .chat,
        "net.whatsapp.WhatsApp": .chat,
        "com.apple.MobileSMS": .chat,
        "com.hnc.Discord": .chat,
        "ru.keepcoder.Telegram": .chat,
        "com.microsoft.VSCode": .editor,
        "com.apple.dt.Xcode": .editor,
        "com.todesktop.230313mzl4w4u92": .editor,
        "dev.zed.Zed": .editor,
        "com.sublimetext.4": .editor,
        "com.apple.TextEdit": .editor,
        "com.apple.Notes": .editor,
        "com.apple.Terminal": .terminal,
        "com.mitchellh.ghostty": .terminal,
        "com.googlecode.iterm2": .terminal,
        "dev.warp.Warp-Stable": .terminal,
    ]

    private static let siteModes: [String: DictationMode] = [
        "gmail": .email,
        "outlook": .email,
        "google chat": .chat,
        "slack": .chat,
        "whatsapp": .chat,
        "discord": .chat,
        "microsoft teams": .chat,
        "messenger": .chat,
    ]

    init(_ context: AppContext) {
        self = Self.mode(forApp: context.bundleIdentifier) ?? Self.mode(forTitle: context.windowTitle) ?? .standard
    }

    func finalize(_ text: String) -> String {
        guard self == .terminal else { return text }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).replacing(#/^[-*•]\s+/#, with: "") }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacing(#/\s+/#, with: " ")
    }

    private static func mode(forApp bundleIdentifier: String?) -> DictationMode? {
        guard let bundleIdentifier else { return nil }
        if bundleIdentifier.hasPrefix("com.jetbrains.") { return .editor }
        return appModes[bundleIdentifier]
    }

    private static func mode(forTitle title: String?) -> DictationMode? {
        guard let title else { return nil }
        return title.split(separator: #/ [-–—|] /#)
            .reversed()
            .lazy
            .compactMap { siteModes[siteName(String($0))] }
            .first
    }

    private static func siteName(_ segment: String) -> String {
        segment.trimmingCharacters(in: .whitespaces)
            .replacing(#/^\(\d+\)\s*/#, with: "")
            .lowercased()
    }
}
