import Foundation

nonisolated final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        lock.withLock { samples += newSamples }
    }

    func drain() -> [Float] {
        lock.withLock {
            defer { samples = [] }
            return samples
        }
    }
}
