import ApplicationServices

enum SelectionRead: Equatable {
    case text(String)
    case empty
    case unknown
}

protocol SelectionReading {
    func selectedText() -> SelectionRead
    /// Nil when the focused element doesn't say.
    func isFocusedElementEditable() -> Bool?
}

struct AXSelectionReader: SelectionReading {
    private static let messagingTimeout: Float = 0.25

    func selectedText() -> SelectionRead {
        guard let element = focusedElement() else { return .unknown }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String else { return .unknown }
        return text.isEmpty ? .empty : .text(text)
    }

    func isFocusedElementEditable() -> Bool? {
        guard let element = focusedElement() else { return nil }
        var answered = false
        for attribute in [kAXSelectedTextAttribute, kAXValueAttribute] {
            var settable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { continue }
            if settable.boolValue { return true }
            answered = true
        }
        return answered ? false : nil
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return element
    }
}
