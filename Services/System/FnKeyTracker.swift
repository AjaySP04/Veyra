enum KeyInput: Equatable {
    case flagsChanged(fn: Bool, control: Bool = false, otherModifiers: Bool = false)
    case keyDown
    case mouseDown
}

struct FnKeyTracker {
    private var held: Gesture?
    private var isCancelled = false

    mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fn: true, control: let control, otherModifiers: false) where held == nil:
            let gesture: Gesture = control ? .act : .dictate
            held = gesture
            isCancelled = false
            return .pressed(gesture)
        case .flagsChanged(fn: false, control: _, otherModifiers: _) where held != nil:
            held = nil
            return isCancelled ? nil : .released
        case .flagsChanged(fn: true, control: _, otherModifiers: true) where held != nil,
             .flagsChanged(fn: true, control: true, otherModifiers: _) where held == .dictate,
             .keyDown where held != nil:
            return cancel()
        // A click moves focus even while Fn is held, so it ends "scratch that" and a pending send; it doesn't stop the recording.
        case .keyDown where held == nil, .mouseDown:
            return .userInput
        default:
            return nil
        }
    }

    private mutating func cancel() -> HotkeyEvent? {
        guard !isCancelled else { return nil }
        isCancelled = true
        return .cancelled
    }
}
