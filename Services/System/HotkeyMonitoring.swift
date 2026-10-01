enum HotkeyEvent: Equatable {
    case pressed
    case released
    case cancelled
    case userInput
}

protocol HotkeyMonitoring: AnyObject {
    var handler: ((HotkeyEvent) -> Void)? { get set }
    func start()
    func stop()
}
