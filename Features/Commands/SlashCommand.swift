import Foundation

/// A spoken "slash compact" or Whisper's "/compact." at the start of a terminal dictation, typed as `/compact` with anything said after it.
struct SlashCommand: Equatable {
    let command: String
    let rest: String

    private static let sentenceWords: Set = ["a", "an", "and", "the", "is", "or", "of", "to"]

    var text: String { rest.isEmpty ? command : "\(command) \(rest)" }

    init(command: String, rest: String) {
        self.command = command
        self.rest = rest
    }

    init?(_ transcript: String) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = text.firstMatch(of: #/^(?i:slash[,.]?\s+|/\s*)([A-Za-z][A-Za-z-]*)(?:[,.!?:;]+)?(?:\s+(.*))?$/#),
              !(match.output.2 ?? "").hasPrefix("/") else { return nil }
        let name = match.output.1.lowercased()
        // "Slash and burn…" is a sentence, not a command.
        guard !Self.sentenceWords.contains(name) else { return nil }
        let rest = (match.output.2.map(String.init) ?? "").trimmingCharacters(in: .whitespaces)
        command = "/" + name
        self.rest = rest
    }
}
