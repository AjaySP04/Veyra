import Foundation

protocol SelectionCopying {
    func copySelection() async -> String?
}

final class ClipboardCopier: SelectionCopying {
    private let pasteboard: Pasteboard
    private let keystrokes: KeystrokeSending
    private let timeout: Duration
    private let interval: Duration
    private let lateRestoreWindow: Duration

    init(
        pasteboard: Pasteboard, keystrokes: KeystrokeSending, timeout: Duration = .milliseconds(300),
        interval: Duration = .milliseconds(20), lateRestoreWindow: Duration = .milliseconds(1500)
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.timeout = timeout
        self.interval = interval
        self.lateRestoreWindow = lateRestoreWindow
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
        guard pasteboard.changeCount != before else {
            restoreIfCopiedLate(original, before: before)
            return nil
        }
        let text = pasteboard.readText()
        pasteboard.restore(original)
        return text?.isEmpty == false ? text : nil
    }

    /// A slow app may answer ⌘C after the timeout; put the user's clipboard back if it does.
    private func restoreIfCopiedLate(_ original: PasteboardSnapshot, before: Int) {
        Task { [pasteboard, interval, lateRestoreWindow] in
            var waited = Duration.zero
            while waited < lateRestoreWindow {
                try? await Task.sleep(for: interval)
                waited += interval
                if pasteboard.changeCount != before {
                    pasteboard.restore(original)
                    return
                }
            }
        }
    }
}
