import Foundation

final class PasteboardTextInserter: TextInserting {
    private let pasteboard: Pasteboard
    private let keystrokes: KeystrokeSending
    private let restoreDelay: Duration

    init(pasteboard: Pasteboard, keystrokes: KeystrokeSending, restoreDelay: Duration = .milliseconds(250)) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.restoreDelay = restoreDelay
    }

    func insert(_ text: String) async throws {
        let original = pasteboard.snapshot()
        pasteboard.write(text)
        let ownChange = pasteboard.changeCount
        keystrokes.sendPaste()
        try await Task.sleep(for: restoreDelay)
        guard pasteboard.changeCount == ownChange else { return }
        pasteboard.restore(original)
    }
}
