import Carbon.HIToolbox
import Testing
@testable import Veyra

@MainActor
struct KeyLayoutTests {
    private let azerty: [CGKeyCode: String] = [
        CGKeyCode(kVK_ANSI_Q): "a", CGKeyCode(kVK_ANSI_A): "q",
        CGKeyCode(kVK_ANSI_W): "z", CGKeyCode(kVK_ANSI_Z): "w",
    ]

    @Test func lettersFollowTheLayout() {
        let layout = KeyLayout { azerty[$0] }
        #expect(layout.keyCode(for: KeyChord.undo.key) == CGKeyCode(kVK_ANSI_W))
        #expect(layout.keyCode(for: KeyChord.selectAll.key) == CGKeyCode(kVK_ANSI_Q))
    }

    @Test func unknownLetterFallsBackToUSPosition() {
        let layout = KeyLayout { _ in nil }
        #expect(layout.keyCode(for: KeyChord.paste.key) == CGKeyCode(kVK_ANSI_V))
    }

    @Test func fixedKeysIgnoreTheLayout() {
        let layout = KeyLayout { _ in "z" }
        #expect(layout.keyCode(for: KeyChord.returnKey.key) == CGKeyCode(kVK_Return))
        #expect(layout.keyCode(for: KeyChord.lineStart.key) == CGKeyCode(kVK_LeftArrow))
    }

    @Test func currentLayoutGivesEveryCommandLetterItsOwnKey() {
        let layout = KeyLayout.current()
        let codes = "abeiuvwz".map { layout.keyCode(for: .character($0)) }
        #expect(Set(codes).count == codes.count)
    }
}
