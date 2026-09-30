import Testing
@testable import Veyra

@MainActor
struct CleanupPromptTests {
    @Test func wrapsTranscriptInTags() {
        #expect(CleanupPrompt.userMessage(for: "hello there") == "<transcript>\nhello there\n</transcript>")
    }

    @Test func systemPromptTreatsTaggedTextAsDictation() {
        #expect(CleanupPrompt.system.contains("<transcript>"))
    }

    @Test func systemPromptFormatsListsAsBullets() {
        #expect(CleanupPrompt.system.contains(#"its own line starting with "- ""#))
        #expect(CleanupPrompt.system.contains(#""- Check the logs.\n- Restart the server.\n- Tell the team.""#))
    }

    @Test(arguments: [
        ("  Hello there.\n", "Hello there."),
        ("<transcript>\nHello there.\n</transcript>", "Hello there."),
        ("  <transcript>Hello there.</transcript>  ", "Hello there."),
        ("Use <b> tags.", "Use <b> tags."),
        ("<transcript>\nFor tomorrow:\n- Fix the bug.\n- Deploy.\n</transcript>", "For tomorrow:\n- Fix the bug.\n- Deploy."),
    ])
    func unwrapsReply(content: String, expected: String) {
        #expect(CleanupPrompt.reply(from: content) == expected)
    }
}
