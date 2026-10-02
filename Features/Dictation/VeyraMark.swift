import AppKit

/// The bold V from the app icon, drawn as a menu bar template image so macOS tints it for light and dark.
enum VeyraMark {
    static let size = NSSize(width: 18, height: 18)
    private static let inset: CGFloat = 1.5

    static func image(tilt degrees: Double) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: -degrees)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
            NSColor.black.setFill()
            path(in: rect.insetBy(dx: inset, dy: inset)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Veyra"
        return image
    }

    private static func path(in rect: NSRect) -> NSBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width, y: rect.minY + (1 - y) * rect.height)
        }
        let path = NSBezierPath()
        path.move(to: point(0.02, 0.06))
        path.line(to: point(0.35, 0.06))
        path.line(to: point(0.50, 0.58))
        path.line(to: point(0.65, 0.06))
        path.line(to: point(0.98, 0.06))
        path.line(to: point(0.63, 0.94))
        path.line(to: point(0.37, 0.94))
        path.close()
        return path
    }
}
