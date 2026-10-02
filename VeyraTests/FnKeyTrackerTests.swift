import Testing
@testable import Veyra

@MainActor
struct FnKeyTrackerTests {
    private let fnDown = KeyInput.flagsChanged(fn: true, otherModifiers: false)
    private let fnUp = KeyInput.flagsChanged(fn: false, otherModifiers: false)
    private let controlFnDown = KeyInput.flagsChanged(fn: true, control: true)
    private let controlOnly = KeyInput.flagsChanged(fn: false, control: true)

    private func events(_ inputs: [KeyInput]) -> [HotkeyEvent] {
        var tracker = FnKeyTracker()
        return inputs.compactMap { tracker.handle($0) }
    }

    @Test func pressAndRelease() {
        #expect(events([fnDown, fnUp]) == [.pressed(.dictate), .released])
    }

    @Test func fnWithAnotherModifierDoesNotPress() {
        #expect(events([.flagsChanged(fn: true, otherModifiers: true), fnUp]).isEmpty)
    }

    @Test func keyDownWhileHeldCancelsOnce() {
        #expect(events([fnDown, .keyDown, .keyDown, fnUp]) == [.pressed(.dictate), .cancelled])
    }

    @Test func addingModifierWhileHeldCancels() {
        #expect(events([fnDown, .flagsChanged(fn: true, otherModifiers: true), fnUp]) == [.pressed(.dictate), .cancelled])
    }

    @Test func keyDownWithoutFnIsUserInput() {
        #expect(events([.keyDown]) == [.userInput])
    }

    @Test func mouseDownWithoutFnIsUserInput() {
        #expect(events([.mouseDown]) == [.userInput])
    }

    @Test func mouseDownWhileHeldIsIgnored() {
        #expect(events([fnDown, .mouseDown, fnUp]) == [.pressed(.dictate), .released])
    }

    @Test func typingAfterReleaseIsUserInput() {
        #expect(events([fnDown, fnUp, .keyDown]) == [.pressed(.dictate), .released, .userInput])
    }

    @Test func worksAgainAfterCancelledPress() {
        #expect(events([fnDown, .keyDown, fnUp, fnDown, fnUp]) == [.pressed(.dictate), .cancelled, .pressed(.dictate), .released])
    }

    @Test func controlThenFnStartsAnAction() {
        #expect(events([controlOnly, controlFnDown, fnUp]) == [.pressed(.act), .released])
    }

    @Test func releasingControlDuringAnActionKeepsIt() {
        #expect(events([controlFnDown, fnDown, fnUp]) == [.pressed(.act), .released])
    }

    @Test func addingControlDuringDictationCancels() {
        #expect(events([fnDown, controlFnDown, fnUp]) == [.pressed(.dictate), .cancelled])
    }

    @Test func controlWithAnotherModifierDoesNotPress() {
        #expect(events([.flagsChanged(fn: true, control: true, otherModifiers: true), fnUp]).isEmpty)
    }

    @Test func controlAloneDoesNothing() {
        #expect(events([controlOnly, .flagsChanged(fn: false)]).isEmpty)
    }
}
