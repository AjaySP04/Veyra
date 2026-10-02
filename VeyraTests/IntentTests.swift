import Testing
@testable import Veyra

@MainActor
struct IntentTests {
    @Test(arguments: [
        ("undo", VoiceCommand.undo),
        ("undo that", .undo),
        ("redo", .redo),
        ("redo that", .redo),
        ("scratch that", .scratchThat),
        ("delete that", .deleteSelection),
        ("delete last word", .deleteLastWord),
        ("delete line", .deleteLine),
        ("bold that", .bold),
        ("italic that", .italic),
        ("underline that", .underline),
        ("select all", .selectAll),
        ("select last word", .selectLastWord),
        ("go to start of line", .lineStart),
        ("go to end of line", .lineEnd),
        ("go to top", .documentStart),
        ("go to bottom", .documentEnd),
        ("new line", .newLine),
        ("new paragraph", .newParagraph),
        ("run it", .pressReturn),
        ("Run that.", .pressReturn),
        ("run this", .pressReturn),
        ("press enter", .pressReturn),
        ("press return", .pressReturn),
        ("hit enter", .pressReturn),
    ])
    func matchesPhrase(phrase: String, expected: VoiceCommand) {
        #expect(Intent(phrase) == .command(expected))
    }

    @Test(arguments: [
        "Undo that.",
        "  Undo that... ",
        "Undo, that!",
        "UNDO THAT",
        "Please undo that.",
        "Undo that, please.",
    ])
    func toleratesWhisperFormatting(transcript: String) {
        #expect(Intent(transcript) == .command(.undo))
    }

    @Test func hyphenatedPhraseMatches() {
        #expect(Intent("New-line.") == .command(.newLine))
    }

    @Test(arguments: [
        "undo the migration",
        "please undo the migration",
        "add a new line of code",
        "please",
        "please please",
        "",
        "hello world",
    ])
    func otherSpeechIsDictated(transcript: String) {
        #expect(Intent(transcript) == .dictate(transcript))
    }

    @Test func everyCommandHasAPhrase() {
        #expect(VoiceCommand.allCases.allSatisfy { !$0.phrases.isEmpty })
    }

    @Test func titleCapitalizesFirstPhrase() {
        #expect(VoiceCommand.newLine.title == "New line")
        #expect(VoiceCommand.documentStart.title == "Go to top")
    }
}
