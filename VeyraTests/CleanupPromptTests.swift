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

    @Test(arguments: [
        ("  Hello there.\n", "Hello there."),
        ("<transcript>\nHello there.\n</transcript>", "Hello there."),
        ("  <transcript>Hello there.</transcript>  ", "Hello there."),
        ("Use <b> tags.", "Use <b> tags."),
    ])
    func unwrapsReply(content: String, expected: String) {
        #expect(CleanupPrompt.reply(from: content) == expected)
    }
}
