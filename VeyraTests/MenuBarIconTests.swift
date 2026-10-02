import AppKit
import Testing
@testable import Veyra

@MainActor
struct MenuBarIconTests {
    @Test(arguments: [
        (DictationState.preparing(progress: nil), MenuBarIcon.mark(swinging: false)),
        (.idle, .mark(swinging: false)),
        (.recording(level: 0.5), .mark(swinging: false)),
        (.acted(message: "Opened Slack"), .mark(swinging: false)),
        (.transcribing, .mark(swinging: true)),
        (.acting, .mark(swinging: true)),
        (.failed(message: "x"), .symbol("exclamationmark.triangle")),
        (.unavailable(message: "x"), .symbol("exclamationmark.triangle")),
    ])
    func iconForState(state: DictationState, expected: MenuBarIcon) {
        #expect(state.menuBarIcon == expected)
    }

    @Test(arguments: [(0.0, 0.0), (0.375, 25.0), (0.75, 0.0), (1.125, -25.0), (1.5, 0.0)])
    func swingFollowsASine(seconds: Double, degrees: Double) {
        #expect(abs(MenuBarIconAnimator.tilt(at: .seconds(seconds)) - degrees) < 0.001)
    }

    @Test func markIsATemplateAtMenuBarSize() {
        let image = VeyraMark.image(tilt: 0)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
    }

    @Test func swingStartsAndSettlesUpright() async throws {
        let animator = MenuBarIconAnimator()
        animator.update(swinging: true)
        #expect(animator.isSwinging)
        try await Task.sleep(for: .milliseconds(200))
        #expect(animator.tilt != 0)
        animator.update(swinging: false)
        #expect(!animator.isSwinging)
        #expect(animator.tilt == 0)
    }
}
