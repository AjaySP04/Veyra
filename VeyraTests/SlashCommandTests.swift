import Testing
@testable import Veyra

struct SlashCommandTests {
    @Test(arguments: [
        ("slash compact", "/compact", ""),
        ("Slash compact.", "/compact", ""),
        ("Slash, handoff.", "/handoff", ""),
        ("Slash exit!", "/exit", ""),
        ("/compact.", "/compact", ""),
        ("/ Compact", "/compact", ""),
        ("Slash handoff, I want to write a handoff for this branch.", "/handoff", "I want to write a handoff for this branch."),
        ("slash review the send branch", "/review", "the send branch"),
        ("Slash code-review.", "/code-review", ""),
    ])
    func turnsSpokenSlashIntoACommand(transcript: String, command: String, rest: String) {
        #expect(SlashCommand(transcript) == SlashCommand(command: command, rest: rest))
    }

    @Test(arguments: [
        "", "slash", "Slash.", "hello world", "use a slash here", "Slash and burn is a farming method",
        "slash 42", "and/or", "/usr/bin/log show",
    ])
    func leavesOtherTextAlone(transcript: String) {
        #expect(SlashCommand(transcript) == nil)
    }

    @Test func joinsCommandAndRest() {
        #expect(SlashCommand(command: "/compact", rest: "").text == "/compact")
        #expect(SlashCommand(command: "/handoff", rest: "for 8.4").text == "/handoff for 8.4")
    }
}
