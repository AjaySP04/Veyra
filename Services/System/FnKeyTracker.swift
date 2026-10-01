enum KeyInput: Equatable {
    case flagsChanged(fn: Bool, otherModifiers: Bool)
    case keyDown
    case mouseDown
}

struct FnKeyTracker {
    private var isHeld = false
    private var isCancelled = false

    mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fn: true, otherModifiers: false) where !isHeld:
            isHeld = true
            isCancelled = false
            return .pressed
        case .flagsChanged(fn: false, otherModifiers: _) where isHeld:
            isHeld = false
            return isCancelled ? nil : .released
        case .flagsChanged(fn: true, otherModifiers: true) where isHeld, .keyDown where isHeld:
            return cancel()
        case .keyDown where !isHeld, .mouseDown where !isHeld:
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
