import Accelerate

nonisolated enum AudioLevel {
    private static let floorDecibels: Float = -50

    static func normalized(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let decibels = 10 * log10(max(vDSP.meanSquare(samples), 1e-10))
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}
