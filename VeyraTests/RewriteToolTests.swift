import Testing
@testable import Veyra

@MainActor
struct RewriteToolTests {
    private let notes = "com.apple.Notes"
    private let copier = FakeCopier()
    private let rewriter = FakeRewriter()
    private let inserter = FakeInserter()
    private let keystrokes = FakeKeystrokes()

    private func tool(_ read: SelectionRead = .unknown, frontmost: String? = "com.apple.Notes") -> RewriteTool {
        RewriteTool(
            selection: FakeSelectionReader(read: read), copier: copier, rewriter: rewriter,
            inserter: inserter, keystrokes: keystrokes, frontmostApp: { frontmost }
        )
    }

    private func context(_ mode: DictationMode = .editor, last: String? = nil, app: String? = "com.apple.Notes") -> ToolContext {
        ToolContext(mode: mode, bundleIdentifier: app, lastInsertion: last.map { LastInsertion(text: $0, bundleIdentifier: app) })
    }

    @Test func definitionTakesAnInstruction() {
        #expect(tool().definition.name == "rewrite")
        #expect(tool().definition.parameters.map(\.name) == ["instruction"])
        #expect(tool().risk == .immediate)
    }

    @Test func lastInsertionComesFirst() async throws {
        let action = try await tool(.text("selected")).prepare(["instruction": "shorter"], in: context(last: "hello world"))
        #expect(rewriter.calls.map { $0.text } == ["hello world"])
        #expect(rewriter.calls.map { $0.instruction } == ["shorter"])
        #expect(copier.copyCount == 0)
        #expect(action.done == "Rewrote your last dictation")
        #expect(inserter.inserted.isEmpty)
        try await action.perform()
        #expect(keystrokes.sentChords == [Array(repeating: .selectCharacterBackward, count: 11)])
        #expect(inserter.inserted == ["Rewritten."])
        #expect(action.insertion == LastInsertion(text: "Rewritten.", bundleIdentifier: notes))
    }

    @Test func accessibilitySelectionIsUsedWithoutCopying() async throws {
        let action = try await tool(.text("selected words")).prepare(["instruction": "formal"], in: context())
        #expect(rewriter.calls.map { $0.text } == ["selected words"])
        #expect(copier.copyCount == 0)
        #expect(action.done == "Rewrote the selection")
        try await action.perform()
        #expect(keystrokes.sentChords.isEmpty)
        #expect(inserter.inserted == ["Rewritten."])
    }

    @Test(arguments: [SelectionRead.empty, .unknown])
    func otherwiseCopiesTheSelection(read: SelectionRead) async throws {
        copier.copied = "copied words"
        let action = try await tool(read).prepare(["instruction": "formal"], in: context())
        #expect(copier.copyCount == 1)
        #expect(rewriter.calls.map { $0.text } == ["copied words"])
        #expect(action.done == "Rewrote the selection")
    }

    @Test func nothingToRewrite() async {
        await #expect(throws: AgentError.noSelection) { try await tool(.empty).prepare(["instruction": "formal"], in: context()) }
        #expect(rewriter.calls.isEmpty)
    }

    @Test func lastInsertionFromAnotherAppIsIgnored() async throws {
        let other = ToolContext(mode: .editor, bundleIdentifier: notes, lastInsertion: LastInsertion(text: "elsewhere", bundleIdentifier: "com.tinyspeck.slackmacgap"))
        let action = try await tool(.text("selected")).prepare(["instruction": "formal"], in: other)
        #expect(rewriter.calls.map { $0.text } == ["selected"])
        #expect(action.done == "Rewrote the selection")
    }

    @Test func tooLong() async {
        let long = String(repeating: "a", count: 4_001)
        await #expect(throws: AgentError.tooLong) { try await tool(.text(long)).prepare(["instruction": "shorter"], in: context()) }
        #expect(rewriter.calls.isEmpty)
    }

    @Test func exactlyAtTheLimitIsRewritten() async throws {
        _ = try await tool(.text(String(repeating: "a", count: 4_000))).prepare(["instruction": "shorter"], in: context())
        #expect(rewriter.calls.count == 1)
    }

    @Test(arguments: [[:], ["instruction": "  "]])
    func missingInstruction(arguments: [String: String]) async {
        await #expect(throws: AgentError.invalidArguments) { try await tool(.text("x")).prepare(arguments, in: context()) }
    }

    @Test func terminalDeletesInsteadOfSelectingAndStaysOneLine() async throws {
        rewriter.result = .success("- First.\n- Second.")
        let ghostty = "com.mitchellh.ghostty"
        let action = try await tool(frontmost: ghostty).prepare(["instruction": "list"], in: context(.terminal, last: "abc", app: ghostty))
        try await action.perform()
        #expect(keystrokes.sentChords == [Array(repeating: .deleteBackward, count: 3)])
        #expect(inserter.inserted == ["First. Second."])
        #expect(inserter.inserted.allSatisfy { !$0.contains("\n") })
    }

    @Test func chainedRewriteSelectsThePreviousRewrite() async throws {
        let first = try await tool().prepare(["instruction": "shorter"], in: context(last: "hello world"))
        try await first.perform()
        rewriter.result = .success("Greetings.")
        let chained = ToolContext(mode: .editor, bundleIdentifier: notes, lastInsertion: first.insertion)
        let second = try await tool().prepare(["instruction": "formal"], in: chained)
        try await second.perform()
        #expect(rewriter.calls.map { $0.text } == ["hello world", "Rewritten."])
        #expect(keystrokes.sentChords.last == Array(repeating: .selectCharacterBackward, count: "Rewritten.".count))
    }

    @Test func appChangedBeforeReplacing() async throws {
        let action = try await tool(.text("selected"), frontmost: "com.tinyspeck.slackmacgap").prepare(["instruction": "formal"], in: context())
        await #expect(throws: AgentError.appChanged) { try await action.perform() }
        #expect(inserter.inserted.isEmpty)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func rewriterErrorsPropagate() async {
        rewriter.result = .failure(AgentError.unavailable)
        await #expect(throws: AgentError.unavailable) { try await tool(.text("x")).prepare(["instruction": "formal"], in: context()) }
    }
}
