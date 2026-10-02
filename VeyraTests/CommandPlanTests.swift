import Testing
@testable import Veyra

@MainActor
struct CommandPlanTests {
    private let notes = "com.apple.Notes"
    private let slack = "com.tinyspeck.slackmacgap"
    private let ghostty = "com.mitchellh.ghostty"

    private func plan(_ command: VoiceCommand, _ mode: DictationMode, app: String? = nil, after insertion: LastInsertion? = nil) -> CommandPlan {
        command.plan(in: CommandContext(mode: mode, bundleIdentifier: app), after: insertion)
    }

    @Test(arguments: [
        (VoiceCommand.undo, KeyChord.undo),
        (.redo, .redo),
        (.deleteSelection, .deleteBackward),
        (.deleteLastWord, .deleteWord),
        (.deleteLine, .deleteLine),
        (.bold, .bold),
        (.italic, .italic),
        (.underline, .underline),
        (.selectAll, .selectAll),
        (.selectLastWord, .selectWordBackward),
        (.lineStart, .lineStart),
        (.lineEnd, .lineEnd),
        (.documentStart, .documentStart),
        (.documentEnd, .documentEnd),
        (.newLine, .softReturn),
    ])
    func standardModeKeys(command: VoiceCommand, chord: KeyChord) {
        #expect(plan(command, .standard) == .keys([chord]))
        #expect(plan(command, .email) == .keys([chord]))
    }

    @Test func newParagraphPressesShiftReturnTwice() {
        #expect(plan(.newParagraph, .standard) == .keys([.softReturn, .softReturn]))
    }

    @Test(arguments: [DictationMode.standard, .email, .chat, .editor])
    func lineBreaksNeverPressPlainReturn(mode: DictationMode) {
        #expect(plan(.newLine, mode, app: notes) == .keys([.softReturn]))
    }

    @Test func chatLineBreaksDoNotSend() {
        #expect(plan(.newLine, .chat, app: slack) == .keys([.softReturn]))
        #expect(plan(.newParagraph, .chat, app: slack) == .keys([.softReturn, .softReturn]))
        #expect(plan(.bold, .chat, app: slack) == .keys([.bold]))
    }

    @Test(arguments: [
        (VoiceCommand.undo, KeyChord.undo),
        (.redo, .redo),
        (.deleteLastWord, .shellDeleteWord),
        (.deleteLine, .shellDeleteLine),
        (.lineStart, .shellLineStart),
        (.lineEnd, .shellLineEnd),
    ])
    func terminalUsesShellKeys(command: VoiceCommand, chord: KeyChord) {
        #expect(plan(command, .terminal, app: ghostty) == .keys([chord]))
    }

    @Test(arguments: [
        VoiceCommand.deleteSelection, .bold, .italic, .underline, .selectAll, .selectLastWord,
        .documentStart, .documentEnd, .newLine, .newParagraph,
    ])
    func terminalBlocksUnsafeCommands(command: VoiceCommand) {
        #expect(plan(command, .terminal, app: ghostty) == .unavailable("\(command.title) isn't available in Terminal"))
    }

    @Test func onlyRunItSendsReturnInTerminal() {
        for command in VoiceCommand.allCases where command != .pressReturn {
            guard case .keys(let chords) = plan(command, .terminal, app: ghostty) else { continue }
            #expect(!chords.contains { $0.key == KeyChord.returnKey.key })
        }
    }

    @Test(arguments: ["com.apple.Notes", "com.apple.TextEdit"])
    func richTextEditorsFormat(app: String) {
        #expect(plan(.bold, .editor, app: app) == .keys([.bold]))
        #expect(plan(.italic, .editor, app: app) == .keys([.italic]))
        #expect(plan(.underline, .editor, app: app) == .keys([.underline]))
    }

    @Test(arguments: ["com.microsoft.VSCode", "com.apple.dt.Xcode", "com.jetbrains.intellij"])
    func codeEditorsBlockFormatting(app: String) {
        for command in [VoiceCommand.bold, .italic, .underline] {
            #expect(plan(command, .editor, app: app) == .unavailable("Formatting isn't available in this app"))
        }
        #expect(plan(.undo, .editor, app: app) == .keys([.undo]))
    }

    @Test func runItPressesReturnInTerminal() {
        #expect(plan(.pressReturn, .terminal, app: ghostty) == .keys([.returnKey]))
    }

    @Test(arguments: [DictationMode.standard, .editor, .chat, .email])
    func runItOnlyWorksInTerminal(mode: DictationMode) {
        #expect(plan(.pressReturn, mode) == .unavailable("Run it only works in Terminal"))
    }

    @Test func scratchDeletesEachInsertedCharacter() {
        let insertion = LastInsertion(text: String(repeating: "a", count: 3), bundleIdentifier: notes)
        #expect(plan(.scratchThat, .editor, app: notes, after: insertion) == .keys(Array(repeating: .deleteBackward, count: 3)))
    }

    @Test func scratchWorksInTerminal() {
        let insertion = LastInsertion(text: String(repeating: "a", count: 2), bundleIdentifier: ghostty)
        #expect(plan(.scratchThat, .terminal, app: ghostty, after: insertion) == .keys([.deleteBackward, .deleteBackward]))
    }

    @Test func scratchClearsACommandThatOwnsTheLine() {
        let insertion = LastInsertion(text: "curl -s https://x.io/?a=1&b=2", bundleIdentifier: ghostty, ownsLine: true)
        #expect(plan(.scratchThat, .terminal, app: ghostty, after: insertion) == .keys([.shellLineEnd, .shellDeleteLine]))
    }

    @Test func scratchWithoutInsertionIsUnavailable() {
        #expect(plan(.scratchThat, .standard) == .unavailable("Nothing to scratch"))
    }

    @Test func scratchInAnotherAppIsUnavailable() {
        let insertion = LastInsertion(text: String(repeating: "a", count: 3), bundleIdentifier: notes)
        #expect(plan(.scratchThat, .chat, app: slack, after: insertion) == .unavailable("Nothing to scratch"))
    }

    @Test func contextReadsModeAndBundleFromApp() {
        let context = CommandContext(AppContext(bundleIdentifier: slack, windowTitle: nil))
        #expect(context == CommandContext(mode: .chat, bundleIdentifier: slack))
    }
}
