enum HotkeyEvent: Equatable {
    case pressed
    case released
    case cancelled
}

protocol HotkeyMonitoring: AnyObject {
    var handler: ((HotkeyEvent) -> Void)? { get set }
    func start()
    func stop()
}
