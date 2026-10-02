import Carbon.HIToolbox
import Foundation
import Testing
@testable import Veyra

@MainActor
struct ClipboardCopierTests {
    private let pasteboard = FakePasteboard()
    private let keystrokes: FakeKeystrokes
    private let copier: ClipboardCopier

    init() {
        keystrokes = FakeKeystrokes(pasteboard: pasteboard)
        copier = ClipboardCopier(pasteboard: pasteboard, keystrokes: keystrokes, timeout: .milliseconds(60), interval: .milliseconds(10))
    }

    @Test func returnsCopiedTextAndRestoresClipboard() async {
        pasteboard.write("mine")
        keystrokes.onSend = { [pasteboard] chords in if chords == [.copy] { pasteboard.write("selected words") } }
        #expect(await copier.copySelection() == "selected words")
        #expect(pasteboard.string == "mine")
        #expect(keystrokes.sentChords == [[.copy]])
    }

    @Test func nothingCopiedLeavesClipboardAlone() async {
        pasteboard.write("mine")
        let before = pasteboard.changeCount
        #expect(await copier.copySelection() == nil)
        #expect(pasteboard.string == "mine")
        #expect(pasteboard.changeCount == before)
    }

    @Test func emptyCopyIsNilButRestored() async {
        pasteboard.write("mine")
        keystrokes.onSend = { [pasteboard] _ in pasteboard.write("") }
        #expect(await copier.copySelection() == nil)
        #expect(pasteboard.string == "mine")
    }

    @Test func chordsAreCopyAndSelectBackward() {
        #expect(KeyChord.copy == KeyChord("c", .maskCommand))
        #expect(KeyChord.selectCharacterBackward == KeyChord(kVK_LeftArrow, .maskShift))
    }

    @Test func lateCopyIsStillRestored() async throws {
        pasteboard.write("mine")
        keystrokes.onSend = { [pasteboard] _ in
            Task { try? await Task.sleep(for: .milliseconds(120)); pasteboard.write("late copy") }
        }
        let late = ClipboardCopier(pasteboard: pasteboard, keystrokes: keystrokes, timeout: .milliseconds(40), interval: .milliseconds(10), lateRestoreWindow: .milliseconds(400))
        #expect(await late.copySelection() == nil)
        try await Task.sleep(for: .milliseconds(500))
        #expect(pasteboard.string == "mine")
    }
}
