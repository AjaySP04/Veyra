import AppKit
import ApplicationServices

struct FrontmostAppContextProvider: AppContextProviding {
    private static let messagingTimeout: Float = 0.25

    func current() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        return AppContext(
            bundleIdentifier: app?.bundleIdentifier,
            windowTitle: app.flatMap { focusedWindowTitle(of: $0.processIdentifier) }
        )
    }

    private func focusedWindowTitle(of processIdentifier: pid_t) -> String? {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        guard let window = attribute(kAXFocusedWindowAttribute, of: application),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let focusedWindow = window as! AXUIElement
        AXUIElementSetMessagingTimeout(focusedWindow, Self.messagingTimeout)
        return attribute(kAXTitleAttribute, of: focusedWindow) as? String
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
