import Foundation

protocol SelectionCopying {
    func copySelection() async -> String?
}

final class ClipboardCopier: SelectionCopying {
    private let pasteboard: Pasteboard
    private let keystrokes: KeystrokeSending
    private let timeout: Duration
    private let interval: Duration

    init(pasteboard: Pasteboard, keystrokes: KeystrokeSending, timeout: Duration = .milliseconds(300), interval: Duration = .milliseconds(20)) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.timeout = timeout
        self.interval = interval
    }

    func copySelection() async -> String? {
        let original = pasteboard.snapshot()
        let before = pasteboard.changeCount
        keystrokes.send([.copy])
        var waited = Duration.zero
        while pasteboard.changeCount == before, waited < timeout {
            try? await Task.sleep(for: interval)
            waited += interval
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.readText()
        pasteboard.restore(original)
        return text?.isEmpty == false ? text : nil
    }
}
