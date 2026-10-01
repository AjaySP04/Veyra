import ApplicationServices

enum SelectionRead: Equatable {
    case text(String)
    case empty
    case unknown
}

protocol SelectionReading {
    func selectedText() -> SelectionRead
}

struct AXSelectionReader: SelectionReading {
    private static let messagingTimeout: Float = 0.25

    func selectedText() -> SelectionRead {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String else { return .unknown }
        return text.isEmpty ? .empty : .text(text)
    }
}
