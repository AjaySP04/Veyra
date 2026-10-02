import Foundation
import Observation

enum MenuBarIcon: Equatable {
    case mark(swinging: Bool)
    case symbol(String)
}

/// Swings the menu bar V like a pendulum while Veyra is busy, and settles it upright when done.
@Observable
final class MenuBarIconAnimator {
    static let amplitude = 25.0
    static let period: Duration = .milliseconds(1500)
    private static let frame: Duration = .milliseconds(33)

    private(set) var tilt = 0.0
    @ObservationIgnored private var swing: Task<Void, Never>?

    var isSwinging: Bool { swing != nil }

    static func tilt(at elapsed: Duration) -> Double {
        amplitude * sin(2 * .pi * (elapsed / period))
    }

    func update(swinging: Bool) {
        guard swinging != isSwinging else { return }
        guard swinging else {
            swing?.cancel()
            swing = nil
            tilt = 0
            return
        }
        let start = ContinuousClock.now
        swing = Task { [weak self] in
            while !Task.isCancelled {
                self?.tilt = Self.tilt(at: .now - start)
                try? await Task.sleep(for: Self.frame)
            }
        }
    }
}
