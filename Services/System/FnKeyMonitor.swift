import AppKit

final class FnKeyMonitor: HotkeyMonitoring {
    var handler: ((HotkeyEvent) -> Void)?

    private var tracker = FnKeyTracker()
    private var monitors: [Any] = []

    func start() {
        stop()
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.process(event)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.process(event)
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        tracker = FnKeyTracker()
    }

    private func process(_ event: NSEvent) {
        guard let input = KeyInput(event), let hotkeyEvent = tracker.handle(input) else { return }
        handler?(hotkeyEvent)
    }
}

private extension KeyInput {
    init?(_ event: NSEvent) {
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != CGEventKeystrokeSender.eventMarker else {
            return nil
        }
        switch event.type {
        case .keyDown:
            self = .keyDown
        case .leftMouseDown, .rightMouseDown:
            self = .mouseDown
        case .flagsChanged:
            let flags = event.modifierFlags
            self = .flagsChanged(
                fn: flags.contains(.function),
                otherModifiers: !flags.isDisjoint(with: [.shift, .control, .option, .command])
            )
        default:
            return nil
        }
    }
}
