import Foundation
@testable import Veyra

@MainActor
final class FakePasteboard: Pasteboard {
    static let textType = "public.utf8-plain-text"

    private(set) var changeCount = 0
    var items: [[String: Data]] = []

    var string: String? {
        items.first?[Self.textType].flatMap { String(data: $0, encoding: .utf8) }
    }

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: items)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        items = snapshot.items
        changeCount += 1
    }

    func write(_ text: String) {
        items = [[Self.textType: Data(text.utf8)]]
        changeCount += 1
    }
}

@MainActor
final class FakeKeystrokes: KeystrokeSending {
    private let pasteboard: FakePasteboard
    var sideEffect: () -> Void = {}
    private(set) var pastedTexts: [String?] = []

    init(pasteboard: FakePasteboard) {
        self.pasteboard = pasteboard
    }

    func sendPaste() {
        pastedTexts.append(pasteboard.string)
        sideEffect()
    }
}
