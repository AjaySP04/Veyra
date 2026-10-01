enum Gesture: Equatable {
    case dictate
    case act
}

enum HotkeyEvent: Equatable {
    case pressed(Gesture)
    case released
    case cancelled
    case userInput
}

protocol HotkeyMonitoring: AnyObject {
    var handler: ((HotkeyEvent) -> Void)? { get set }
    func start()
    func stop()
}
