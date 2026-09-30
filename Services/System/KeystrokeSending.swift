import Carbon.HIToolbox
import CoreGraphics

protocol KeystrokeSending {
    func sendPaste()
}

struct CGEventKeystrokeSender: KeystrokeSending {
    func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isKeyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isKeyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
