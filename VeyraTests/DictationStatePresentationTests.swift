import Testing
@testable import Veyra

@MainActor
struct DictationStatePresentationTests {
    @Test(arguments: [
        (DictationState.preparing(progress: nil), "Loading speech model…"),
        (.preparing(progress: 0.42), "Downloading speech model… 42%"),
        (.preparing(progress: 1), "Loading speech model…"),
        (.idle, "Hold Fn to dictate"),
        (.unavailable(message: "Offline"), "Offline"),
        (.acting, "Working…"),
        (.acted(message: "Opened Slack"), "Opened Slack"),
    ])
    func statusText(state: DictationState, expected: String) {
        #expect(state.statusText == expected)
    }

    @Test(arguments: [
        (DictationState.recording(level: 0), true),
        (.transcribing, true),
        (.failed(message: "x"), true),
        (.idle, false),
        (.preparing(progress: nil), false),
        (.unavailable(message: "x"), false),
        (.acting, true),
        (.acted(message: "x"), true),
    ])
    func overlayVisibility(state: DictationState, expected: Bool) {
        #expect(state.showsOverlay == expected)
    }
}
