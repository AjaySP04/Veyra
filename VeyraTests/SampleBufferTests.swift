import Testing
@testable import Veyra

struct SampleBufferTests {
    @Test func drainReturnsAppendedSamplesInOrder() {
        let buffer = SampleBuffer()
        buffer.append([1, 2])
        buffer.append([3])
        #expect(buffer.drain() == [1, 2, 3])
    }

    @Test func drainEmptiesTheBuffer() {
        let buffer = SampleBuffer()
        buffer.append([1])
        _ = buffer.drain()
        #expect(buffer.drain().isEmpty)
    }
}
