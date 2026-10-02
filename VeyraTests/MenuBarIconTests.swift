import AppKit
import Testing
@testable import Veyra

@MainActor
struct MenuBarIconTests {
    @Test(arguments: [
        (DictationState.preparing(progress: nil), MenuBarIcon.mark(swinging: false)),
        (.idle, .mark(swinging: false)),
        (.recording(level: 0.5), .mark(swinging: false)),
        (.acted(message: "Opened Slack"), .mark(swinging: false)),
        (.transcribing, .mark(swinging: true)),
        (.acting, .mark(swinging: true)),
        (.failed(message: "x"), .symbol("exclamationmark.triangle")),
        (.unavailable(message: "x"), .symbol("exclamationmark.triangle")),
    ])
    func iconForState(state: DictationState, expected: MenuBarIcon) {
        #expect(state.menuBarIcon == expected)
    }

    @Test func restPoseIsCalm() {
        #expect(MarkPose.rest == MarkPose(tilt: 0, lift: 0, swell: [0, 0, 0, 0, 0]))
    }

    @Test func waveTravelsLeftToRight() {
        let step = MenuBarIconAnimator.barDelay
        for seconds in stride(from: 0.0, through: 1.6, by: 0.2) {
            let now = MenuBarIconAnimator.pose(at: .seconds(seconds))
            let later = MenuBarIconAnimator.pose(at: .seconds(seconds) + step)
            for bar in 0..<4 {
                #expect(abs(later.swell[bar + 1] - now.swell[bar]) < 0.0001)
            }
        }
    }

    @Test func boatRidesTheMiddleBarAndStaysGentle() {
        for seconds in stride(from: 0.0, through: 3.2, by: 0.05) {
            let pose = MenuBarIconAnimator.pose(at: .seconds(seconds))
            #expect(abs(pose.tilt) <= MenuBarIconAnimator.maxTilt + 0.0001)
            #expect(abs(pose.lift) <= MenuBarIconAnimator.maxLift + 0.0001)
            #expect(pose.swell.allSatisfy { abs($0) <= 1.0001 })
            #expect(abs(pose.lift - MenuBarIconAnimator.maxLift * pose.swell[2]) < 0.0001)
        }
    }

    @Test func markIsATemplateAtMenuBarSize() {
        let image = VeyraMark.image(pose: .rest)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
    }

    @Test func floatingStartsAndSettlesCalm() async throws {
        let animator = MenuBarIconAnimator()
        animator.update(swinging: true)
        #expect(animator.isSwinging)
        try await Task.sleep(for: .milliseconds(200))
        #expect(animator.pose != .rest)
        animator.update(swinging: false)
        #expect(!animator.isSwinging)
        #expect(animator.pose == .rest)
    }

    private func alpha(_ image: NSImage, rows: Range<Int>) -> [UInt8] {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
        NSGraphicsContext.restoreGraphicsState()
        return rows.flatMap { y in (0..<36).map { x in UInt8(rep.colorAt(x: x, y: y)!.alphaComponent * 255) } }
    }

    @Test func wavesAndBoatBothMoveWhileFloating() {
        let calm = VeyraMark.image(pose: .rest)
        let rolling = VeyraMark.image(pose: MenuBarIconAnimator.pose(at: .milliseconds(300)))
        let bars = 26..<36, letter = 0..<20
        #expect(alpha(calm, rows: bars).contains { $0 > 128 })
        #expect(alpha(calm, rows: bars) != alpha(rolling, rows: bars))
        #expect(alpha(calm, rows: letter) != alpha(rolling, rows: letter))
    }

    @Test func boatStaysInsideTheIcon() {
        for seconds in stride(from: 0.0, through: 1.6, by: 0.1) {
            let image = VeyraMark.image(pose: MenuBarIconAnimator.pose(at: .seconds(seconds)))
            #expect(!alpha(image, rows: 0..<1).contains { $0 > 0 })
        }
    }
}
