import Testing
@testable import Veyra

@MainActor
struct SendToolTests {
    private let slack = "com.tinyspeck.slackmacgap"
    private let inserter = FakeInserter()
    private let keystrokes = FakeKeystrokes()

    private func tool(frontmost: @escaping () -> String? = { "com.tinyspeck.slackmacgap" }) -> SendTool {
        SendTool(inserter: inserter, keystrokes: keystrokes, frontmostApp: frontmost)
    }

    private func context(_ mode: DictationMode = .chat, app: String = "com.tinyspeck.slackmacgap", untouched: @escaping () -> Bool = { true }) -> ToolContext {
        ToolContext(mode: mode, bundleIdentifier: app, lastInsertion: nil, isUntouched: untouched)
    }

    @Test func definitionTakesAMessageAndNeedsConfirmation() {
        #expect(tool().definition.name == "send")
        #expect(tool().definition.parameters.map(\.name) == ["message"])
        #expect(tool().risk == .confirm)
    }

    @Test func pastesTheDraftAndHoldsTheSendKey() async throws {
        let action = try await tool().prepare(["message": "  Sounds good, see you at 5!\n"], in: context())
        #expect(inserter.inserted.isEmpty)
        try await action.perform()
        #expect(inserter.inserted == ["Sounds good, see you at 5!"])
        #expect(keystrokes.sentChords.isEmpty)
        #expect(action.done == "Say “send it” to send")
        #expect(action.failure == "Couldn't write the message")
        #expect(action.insertion == LastInsertion(text: "Sounds good, see you at 5!", bundleIdentifier: slack))
        let confirmation = try #require(action.confirmation)
        #expect(confirmation.done == "Sent")
        #expect(confirmation.failure == "Couldn't send")
        try await confirmation.perform()
        #expect(keystrokes.sentChords == [[.returnKey]])
        #expect(inserter.inserted.count == 1)
    }

    @Test func emailPromptMentionsTheEmailAndUsesMailsKey() async throws {
        let action = try await tool(frontmost: { "com.apple.mail" }).prepare(["message": "Thanks, Sam"], in: context(.email, app: "com.apple.mail"))
        #expect(action.done == "Say “send it” to send the email")
        try await action.perform()
        try await action.confirmation?.perform()
        #expect(keystrokes.sentChords == [[.sendMail]])
    }

    @Test func keepsLineBreaksInTheMessage() async throws {
        let action = try await tool().prepare(["message": "Hi Sam,\n\nThanks!"], in: context())
        try await action.perform()
        #expect(inserter.inserted == ["Hi Sam,\n\nThanks!"])
    }

    @Test(arguments: [("\"Sounds good\"", "Sounds good"), ("“On my way”", "On my way"), ("'ok'", "'ok'"), ("\"Hi\" she said", "\"Hi\" she said")])
    func stripsWrappingQuotes(raw: String, expected: String) async throws {
        let action = try await tool().prepare(["message": raw], in: context())
        #expect(action.insertion?.text == expected)
    }

    @Test(arguments: ["", "   ", "\"\"", "“ ”"])
    func emptyIsInvalid(raw: String) async {
        await #expect(throws: AgentError.invalidArguments) { try await tool().prepare(["message": raw], in: context()) }
    }

    @Test func missingMessageIsInvalid() async {
        await #expect(throws: AgentError.invalidArguments) { try await tool().prepare([:], in: context()) }
    }

    @Test func refusesOverTheLimit() async throws {
        _ = try await tool().prepare(["message": String(repeating: "a", count: 4_000)], in: context())
        await #expect(throws: AgentError.messageTooLong) {
            try await tool().prepare(["message": String(repeating: "a", count: 4_001)], in: context())
        }
    }

    @Test(arguments: [DictationMode.standard, .editor, .terminal])
    func refusesOutsideChatAndEmail(mode: DictationMode) async {
        await #expect(throws: AgentError.notMessaging) { try await tool().prepare(["message": "hi"], in: context(mode)) }
        #expect(inserter.inserted.isEmpty)
    }

    @Test func appChangedBeforePreparing() async {
        await #expect(throws: AgentError.appChanged) {
            try await tool(frontmost: { "com.apple.Notes" }).prepare(["message": "hi"], in: context())
        }
    }

    @Test func appChangedBeforePasting() async throws {
        var frontmost: String? = slack
        let action = try await tool(frontmost: { frontmost }).prepare(["message": "hi"], in: context())
        frontmost = "com.apple.Notes"
        await #expect(throws: AgentError.appChanged) { try await action.perform() }
        #expect(inserter.inserted.isEmpty)
    }

    @Test func appChangedBeforeSending() async throws {
        var frontmost: String? = slack
        let action = try await tool(frontmost: { frontmost }).prepare(["message": "hi"], in: context())
        try await action.perform()
        frontmost = "com.apple.Notes"
        await #expect(throws: AgentError.appChanged) { try await action.confirmation?.perform() }
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func typingBeforePastingCancels() async throws {
        let action = try await tool().prepare(["message": "hi"], in: context(untouched: { false }))
        await #expect(throws: AgentError.interrupted) { try await action.perform() }
        #expect(inserter.inserted.isEmpty)
    }

    @Test func typingBeforeSendingCancels() async throws {
        var untouched = true
        let action = try await tool().prepare(["message": "hi"], in: context(untouched: { untouched }))
        try await action.perform()
        untouched = false
        await #expect(throws: AgentError.interrupted) { try await action.confirmation?.perform() }
        #expect(keystrokes.sentChords.isEmpty)
    }
}
