import Foundation

enum VoiceCommand: String, CaseIterable {
    case undo, redo
    case scratchThat, deleteSelection, deleteLastWord, deleteLine
    case bold, italic, underline
    case selectAll, selectLastWord
    case lineStart, lineEnd, documentStart, documentEnd
    case newLine, newParagraph

    private static let commandsByPhrase = Dictionary(
        uniqueKeysWithValues: allCases.flatMap { command in command.phrases.map { ($0, command) } }
    )

    init?(phrase: String) {
        guard let command = Self.commandsByPhrase[Self.normalized(phrase)] else { return nil }
        self = command
    }

    var phrases: [String] {
        switch self {
        case .undo: ["undo", "undo that"]
        case .redo: ["redo", "redo that"]
        case .scratchThat: ["scratch that"]
        case .deleteSelection: ["delete that"]
        case .deleteLastWord: ["delete last word"]
        case .deleteLine: ["delete line"]
        case .bold: ["bold that"]
        case .italic: ["italic that"]
        case .underline: ["underline that"]
        case .selectAll: ["select all"]
        case .selectLastWord: ["select last word"]
        case .lineStart: ["go to start of line"]
        case .lineEnd: ["go to end of line"]
        case .documentStart: ["go to top"]
        case .documentEnd: ["go to bottom"]
        case .newLine: ["new line"]
        case .newParagraph: ["new paragraph"]
        }
    }

    var title: String {
        let phrase = phrases[0]
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    private static func normalized(_ text: String) -> String {
        var words = text.lowercased()
            .replacing(#/[^a-z0-9\s]/#, with: " ")
            .split(whereSeparator: \.isWhitespace)
        if words.first == "please" { words.removeFirst() }
        if words.last == "please" { words.removeLast() }
        return words.joined(separator: " ")
    }
}
