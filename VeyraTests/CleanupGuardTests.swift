import Testing
@testable import Veyra

@MainActor
struct CleanupGuardTests {
    @Test(arguments: [
        ("hey team uh basically payment integration is done and testing is left",
         "Hey team, payment integration is done and testing is left."),
        ("so um i think we should you know move the meeting to thursday because uh friday doesn't work for me",
         "I think we should move the meeting to Thursday because Friday doesn’t work for me."),
        ("what time is the standup tomorrow", "What time is the standup tomorrow?"),
        ("i red the book yesterday", "I read the book yesterday."),
        ("see you at the stand up", "See you at the stand-up."),
        ("okay", "Okay."),
    ])
    func acceptsLightCleanup(original: String, cleaned: String) {
        #expect(CleanupGuard.accepts(original: original, cleaned: cleaned))
    }

    @Test(arguments: [
        ("what time is the standup tomorrow",
         #"I'm not sure what you're referring to, but I think you meant to ask "What time is the stand-up comedy show tomorrow?""#),
        ("can you write me a poem about the ocean",
         "The ocean rolls in silver light, waves that whisper through the night."),
        ("hey team uh basically payment integration is done and testing is left", "Payment is done."),
        ("hello there", ""),
        ("hello there", " … "),
    ])
    func rejectsDrift(original: String, cleaned: String) {
        #expect(!CleanupGuard.accepts(original: original, cleaned: cleaned))
    }

    @Test func wordsAreLowercasedWithApostrophesNormalized() {
        #expect(CleanupGuard.words(in: "Friday DOESN’T work, ok?") == ["friday", "doesn't", "work", "ok"])
    }
}
