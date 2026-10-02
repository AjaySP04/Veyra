import Foundation
import Observation

enum MenuBarIcon: Equatable {
    case mark(swinging: Bool)
    case symbol(String)
}

/// How the menu bar V sits on its waves: `swell` is each bar's rise from −1 to 1, `lift` and `tilt` move the V.
struct MarkPose: Equatable {
    var tilt: Double
    var lift: Double
    var swell: [Double]

    static let rest = MarkPose(tilt: 0, lift: 0, swell: [0, 0, 0, 0, 0])
}

/// Floats the menu bar V like a boat on rolling waves while Veyra is busy, and calms it when done.
@Observable
final class MenuBarIconAnimator {
    static let period: Duration = .milliseconds(1600)
    static let barDelay: Duration = .milliseconds(240)
    static let maxTilt = 8.0
    static let maxLift = 0.03
    private static let frame: Duration = .milliseconds(33)

    private(set) var pose = MarkPose.rest
    @ObservationIgnored private var floating: Task<Void, Never>?

    var isSwinging: Bool { floating != nil }

    static func pose(at elapsed: Duration) -> MarkPose {
        let phase = 2 * Double.pi * (elapsed / period)
        let step = 2 * Double.pi * (barDelay / period)
        let swell = (0..<5).map { sin(phase - Double($0) * step) }
        let boat = phase - 2 * step
        return MarkPose(tilt: maxTilt * cos(boat), lift: maxLift * swell[2], swell: swell)
    }

    func update(swinging: Bool) {
        guard swinging != isSwinging else { return }
        guard swinging else {
            floating?.cancel()
            floating = nil
            pose = .rest
            return
        }
        let start = ContinuousClock.now
        floating = Task { [weak self] in
            while !Task.isCancelled {
                self?.pose = Self.pose(at: .now - start)
                try? await Task.sleep(for: Self.frame)
            }
        }
    }
}
