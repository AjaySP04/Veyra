import Testing
@testable import Veyra

@MainActor
struct TranscriptCleanerTests {
    @Test(arguments: [
        ("[BLANK_AUDIO]", ""),
        ("  Hello   world.  ", "Hello world."),
        ("Hello [MUSIC] there", "Hello there"),
        ("♪ ♪", ""),
        ("(upbeat music)", ""),
        ("*sighs*", ""),
        ("Call me (maybe) later", "Call me (maybe) later"),
        ("(laughs) Okay, so (laughs)", "(laughs) Okay, so (laughs)"),
        ("*sighs* fine *laughs*", "*sighs* fine *laughs*"),
    ])
    func cleans(raw: String, expected: String) {
        #expect(TranscriptCleaner.clean(raw) == expected)
    }
}
