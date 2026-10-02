import Testing
@testable import Veyra

@MainActor
struct ShellToolTests {
    private let ghostty = "com.mitchellh.ghostty"
    private let inserter = FakeInserter()
    private let keystrokes = FakeKeystrokes()

    private func tool(frontmost: @escaping () -> String? = { "com.mitchellh.ghostty" }) -> ShellTool {
        ShellTool(inserter: inserter, keystrokes: keystrokes, frontmostApp: frontmost)
    }

    private func context(_ mode: DictationMode = .terminal, untouched: @escaping () -> Bool = { true }) -> ToolContext {
        ToolContext(mode: mode, bundleIdentifier: ghostty, lastInsertion: nil, isUntouched: untouched)
    }

    @Test func definitionTakesACommand() {
        #expect(tool().definition.name == "shell")
        #expect(tool().definition.parameters.map(\.name) == ["command"])
        #expect(tool().risk == .immediate)
    }

    @Test func clearsThePromptLineThenPastesWithoutReturn() async throws {
        let action = try await tool().prepare(["command": "git status\n"], in: context())
        #expect(keystrokes.sentChords.isEmpty)
        #expect(inserter.inserted.isEmpty)
        try await action.perform()
        #expect(keystrokes.sentChords == [[.shellLineEnd, .shellDeleteLine]])
        #expect(inserter.inserted == ["git status"])
        #expect(!keystrokes.sentChords.joined().contains(.returnKey))
        #expect(action.done == "Command ready. Check it, then press Return")
        #expect(action.failure == "Couldn't write the command")
        #expect(action.insertion == LastInsertion(text: "git status", bundleIdentifier: ghostty, ownsLine: true))
    }

    @Test func warnsAboutRiskyCommands() async throws {
        let action = try await tool().prepare(["command": "rm -rf node_modules"], in: context())
        #expect(action.done == "Check carefully: this deletes files")
    }

    @Test(arguments: [DictationMode.standard, .editor, .chat, .email])
    func refusesOutsideATerminal(mode: DictationMode) async {
        await #expect(throws: AgentError.notTerminal) { try await tool().prepare(["command": "ls"], in: context(mode)) }
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func refusesAMultilineCommand() async {
        await #expect(throws: AgentError.badCommand) { try await tool().prepare(["command": "cd /\nrm -rf *"], in: context()) }
    }

    @Test func missingCommandIsInvalid() async {
        await #expect(throws: AgentError.invalidArguments) { try await tool().prepare([:], in: context()) }
    }

    @Test func appChangedBeforePreparing() async {
        await #expect(throws: AgentError.appChanged) {
            try await tool(frontmost: { "com.apple.Notes" }).prepare(["command": "ls"], in: context())
        }
    }

    @Test func appChangedBeforeWriting() async throws {
        var frontmost: String? = ghostty
        let action = try await tool(frontmost: { frontmost }).prepare(["command": "ls"], in: context())
        frontmost = "com.apple.Notes"
        await #expect(throws: AgentError.appChanged) { try await action.perform() }
        #expect(keystrokes.sentChords.isEmpty)
        #expect(inserter.inserted.isEmpty)
    }

    @Test func typingCancelsTheCommand() async throws {
        let action = try await tool().prepare(["command": "ls"], in: context(untouched: { false }))
        await #expect(throws: AgentError.interrupted) { try await action.perform() }
        #expect(keystrokes.sentChords.isEmpty)
        #expect(inserter.inserted.isEmpty)
    }
}
