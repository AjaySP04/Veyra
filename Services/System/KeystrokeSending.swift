import CoreGraphics

protocol KeystrokeSending {
    func send(_ chords: [KeyChord])
}

struct CGEventKeystrokeSender: KeystrokeSending {
    static let eventMarker: Int64 = 0x5645_5952_41

    func send(_ chords: [KeyChord]) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for chord in chords {
            for isKeyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: chord.key, keyDown: isKeyDown)
                event?.flags = chord.flags
                event?.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
