import AppKit

/// The bold V over a short sound wave, from the app icon, drawn as a menu bar template image so macOS tints
/// it for light and dark. While Veyra works, the bars roll and the V rides them like a boat.
enum VeyraMark {
    static let size = NSSize(width: 18, height: 18)

    private static let letterTop: CGFloat = 0.08
    private static let letterBottom: CGFloat = 0.64
    private static let waveTop: CGFloat = 0.70
    private static let waveBottom: CGFloat = 1.0
    private static let barHeights: [CGFloat] = [0.55, 0.85, 1.0, 0.85, 0.55]
    private static let barWidth: CGFloat = 0.10
    private static let barGap: CGFloat = 0.065

    static func image(pose: MarkPose) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let frame = rect.insetBy(dx: 1, dy: 0.75)
            NSColor.black.setFill()
            letter(in: frame, tilt: pose.tilt, lift: pose.lift).fill()
            wave(in: frame, swell: pose.swell).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Veyra"
        return image
    }

    /// Maps unit coordinates (origin top-left) into the frame.
    private static func point(_ x: CGFloat, _ y: CGFloat, in frame: NSRect) -> NSPoint {
        NSPoint(x: frame.minX + x * frame.width, y: frame.minY + (1 - y) * frame.height)
    }

    private static func letter(in frame: NSRect, tilt degrees: Double, lift: Double) -> NSBezierPath {
        func letterY(_ t: CGFloat) -> CGFloat { letterTop + t * (letterBottom - letterTop) - lift }
        let corners: [(CGFloat, CGFloat)] = [
            (0.14, 0), (0.39, 0), (0.50, 0.55), (0.61, 0), (0.86, 0), (0.60, 1), (0.40, 1),
        ]
        let path = NSBezierPath()
        for (index, (x, t)) in corners.enumerated() {
            let corner = point(x, letterY(t), in: frame)
            index == 0 ? path.move(to: corner) : path.line(to: corner)
        }
        path.close()

        let pivot = point(0.5, (letterTop + letterBottom) / 2 - lift, in: frame)
        var transform = AffineTransform(translationByX: -pivot.x, byY: -pivot.y)
        transform.append(AffineTransform(rotationByDegrees: -degrees))
        transform.append(AffineTransform(translationByX: pivot.x, byY: pivot.y))
        path.transform(using: transform)
        return path
    }

    private static func wave(in frame: NSRect, swell: [Double]) -> NSBezierPath {
        let path = NSBezierPath()
        let centre = (waveTop + waveBottom) / 2
        let total = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * barGap
        for (index, height) in barHeights.enumerated() {
            let x = 0.5 - total / 2 + CGFloat(index) * (barWidth + barGap)
            let rise = index < swell.count ? swell[index] : 0
            let half = height * (0.83 + 0.17 * rise) * (waveBottom - waveTop) / 2
            let top = point(x, centre - half, in: frame)
            let bar = NSRect(x: top.x, y: top.y - 2 * half * frame.height, width: barWidth * frame.width, height: 2 * half * frame.height)
            path.append(NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2))
        }
        return path
    }
}
