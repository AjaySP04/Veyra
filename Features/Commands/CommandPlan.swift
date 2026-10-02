struct CommandContext: Equatable {
    let mode: DictationMode
    let bundleIdentifier: String?

    init(mode: DictationMode, bundleIdentifier: String?) {
        self.mode = mode
        self.bundleIdentifier = bundleIdentifier
    }

    init(_ app: AppContext) {
        self.init(mode: DictationMode(app), bundleIdentifier: app.bundleIdentifier)
    }
}

struct LastInsertion: Equatable {
    let text: String
    let bundleIdentifier: String?
    /// A shell command written after ⌃U cleared the prompt, so the whole line is Veyra's. Shells may lengthen a paste (url-quote-magic), so it's removed with ⌃E ⌃U rather than counted ⌫.
    var ownsLine = false

    var characterCount: Int { text.count }
}

enum CommandPlan: Equatable {
    case keys([KeyChord])
    case unavailable(String)
}

extension VoiceCommand {
    private static let blockedInTerminal: Set<VoiceCommand> = [
        .deleteSelection, .bold, .italic, .underline, .selectAll, .selectLastWord,
        .documentStart, .documentEnd, .newLine, .newParagraph,
    ]
    private static let formatting: Set<VoiceCommand> = [.bold, .italic, .underline]
    private static let richTextEditors: Set<String> = ["com.apple.TextEdit", "com.apple.Notes"]

    func plan(in context: CommandContext, after lastInsertion: LastInsertion?) -> CommandPlan {
        let isTerminal = context.mode == .terminal
        if isTerminal, Self.blockedInTerminal.contains(self) {
            return .unavailable("\(title) isn't available in Terminal")
        }
        if context.mode == .editor, Self.formatting.contains(self),
           !Self.richTextEditors.contains(context.bundleIdentifier ?? "") {
            return .unavailable("Formatting isn't available in this app")
        }
        switch self {
        case .undo: return .keys([.undo])
        case .redo: return .keys([.redo])
        case .scratchThat:
            guard let lastInsertion, lastInsertion.bundleIdentifier == context.bundleIdentifier else {
                return .unavailable("Nothing to scratch")
            }
            if isTerminal, lastInsertion.ownsLine { return .keys([.shellLineEnd, .shellDeleteLine]) }
            return .keys(Array(repeating: .deleteBackward, count: lastInsertion.characterCount))
        case .deleteSelection: return .keys([.deleteBackward])
        case .deleteLastWord: return .keys([isTerminal ? .shellDeleteWord : .deleteWord])
        case .deleteLine: return .keys([isTerminal ? .shellDeleteLine : .deleteLine])
        case .bold: return .keys([.bold])
        case .italic: return .keys([.italic])
        case .underline: return .keys([.underline])
        case .selectAll: return .keys([.selectAll])
        case .selectLastWord: return .keys([.selectWordBackward])
        case .lineStart: return .keys([isTerminal ? .shellLineStart : .lineStart])
        case .lineEnd: return .keys([isTerminal ? .shellLineEnd : .lineEnd])
        case .documentStart: return .keys([.documentStart])
        case .documentEnd: return .keys([.documentEnd])
        case .newLine: return .keys([.softReturn])
        case .newParagraph: return .keys([.softReturn, .softReturn])
        // Return sends messages and submits forms elsewhere, which needs confirmation (8.4).
        case .pressReturn: return isTerminal ? .keys([.returnKey]) : .unavailable("\(title) only works in Terminal")
        }
    }
}
