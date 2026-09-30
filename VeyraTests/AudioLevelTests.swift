import Testing
@testable import Veyra

struct AudioLevelTests {
    @Test func emptyIsSilent() {
        #expect(AudioLevel.normalized([]) == 0)
    }

    @Test func silenceIsZero() {
        #expect(AudioLevel.normalized(Array(repeating: 0, count: 1_000)) == 0)
    }

    @Test func fullScaleIsOne() {
        #expect(AudioLevel.normalized(Array(repeating: 1, count: 1_000)) == 1)
    }

    @Test func minusTwentyDecibelsMapsLinearly() {
        let level = AudioLevel.normalized(Array(repeating: 0.1, count: 1_000))
        #expect(abs(level - 0.6) < 0.001)
    }
}
