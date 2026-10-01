import Foundation
import Testing
@testable import Veyra

@MainActor
struct PasteboardTextInserterTests {
    private let pasteboard = FakePasteboard()
    private let keystrokes: FakeKeystrokes
    private let inserter: PasteboardTextInserter

    init() {
        keystrokes = FakeKeystrokes(pasteboard: pasteboard)
        inserter = PasteboardTextInserter(pasteboard: pasteboard, keystrokes: keystrokes, restoreDelay: .zero)
    }

    @Test func pastesTextThenRestoresClipboard() async throws {
        pasteboard.write("old")
        try await inserter.insert("hello")
        #expect(keystrokes.pastedTexts == ["hello"])
        #expect(pasteboard.string == "old")
    }

    @Test func pastesWithCommandV() async throws {
        try await inserter.insert("hello")
        #expect(keystrokes.sentChords == [[.paste]])
    }

    @Test func restoresNonTextClipboard() async throws {
        let original: [[String: Data]] = [
            ["public.png": Data([1, 2, 3]), "public.tiff": Data([4])],
            ["public.file-url": Data("file:///tmp/a".utf8)],
        ]
        pasteboard.items = original
        try await inserter.insert("hello")
        #expect(pasteboard.items == original)
    }

    @Test func restoresEmptyClipboard() async throws {
        try await inserter.insert("hello")
        #expect(pasteboard.items.isEmpty)
    }

    @Test func keepsClipboardChangedByAnotherApp() async throws {
        pasteboard.write("old")
        keystrokes.sideEffect = { [pasteboard] in pasteboard.write("copied elsewhere") }
        try await inserter.insert("hello")
        #expect(pasteboard.string == "copied elsewhere")
    }
}
