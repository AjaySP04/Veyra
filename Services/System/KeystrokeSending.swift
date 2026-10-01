import CoreGraphics

protocol KeystrokeSending {
    func send(_ chords: [KeyChord])
}

struct CGEventKeystrokeSender: KeystrokeSending {
    static let eventMarker: Int64 = 0x5645_5952_41

    func send(_ chords: [KeyChord]) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let layout = KeyLayout.current()
        for chord in chords {
            let code = layout.keyCode(for: chord.key)
            for isKeyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isKeyDown)
                event?.flags = chord.flags
                event?.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
