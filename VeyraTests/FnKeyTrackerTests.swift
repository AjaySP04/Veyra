import Testing
@testable import Veyra

@MainActor
struct FnKeyTrackerTests {
    private let fnDown = KeyInput.flagsChanged(fn: true, otherModifiers: false)
    private let fnUp = KeyInput.flagsChanged(fn: false, otherModifiers: false)

    private func events(_ inputs: [KeyInput]) -> [HotkeyEvent] {
        var tracker = FnKeyTracker()
        return inputs.compactMap { tracker.handle($0) }
    }

    @Test func pressAndRelease() {
        #expect(events([fnDown, fnUp]) == [.pressed, .released])
    }

    @Test func fnWithAnotherModifierDoesNotPress() {
        #expect(events([.flagsChanged(fn: true, otherModifiers: true), fnUp]).isEmpty)
    }

    @Test func keyDownWhileHeldCancelsOnce() {
        #expect(events([fnDown, .keyDown, .keyDown, fnUp]) == [.pressed, .cancelled])
    }

    @Test func addingModifierWhileHeldCancels() {
        #expect(events([fnDown, .flagsChanged(fn: true, otherModifiers: true), fnUp]) == [.pressed, .cancelled])
    }

    @Test func keyDownWithoutFnIsUserInput() {
        #expect(events([.keyDown]) == [.userInput])
    }

    @Test func mouseDownWithoutFnIsUserInput() {
        #expect(events([.mouseDown]) == [.userInput])
    }

    @Test func mouseDownWhileHeldIsIgnored() {
        #expect(events([fnDown, .mouseDown, fnUp]) == [.pressed, .released])
    }

    @Test func typingAfterReleaseIsUserInput() {
        #expect(events([fnDown, fnUp, .keyDown]) == [.pressed, .released, .userInput])
    }

    @Test func worksAgainAfterCancelledPress() {
        #expect(events([fnDown, .keyDown, fnUp, fnDown, fnUp]) == [.pressed, .cancelled, .pressed, .released])
    }
}
