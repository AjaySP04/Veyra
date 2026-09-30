import AVFoundation
import Testing
@testable import Veyra

struct AudioResamplerTests {
    private let stereo48k = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    @Test func convertsStereo48kToMono16k() throws {
        let resampler = try AudioResampler(inputFormat: stereo48k)
        let counts = try (0..<10).map { _ in try resampler.convert(sine(frames: 4_800)).count }
        #expect(counts.dropFirst().allSatisfy { $0 == 1_600 })
        #expect(counts[0] >= 1_280)
    }

    @Test func preservesSignal() throws {
        let resampler = try AudioResampler(inputFormat: stereo48k)
        let output = try (0..<3).flatMap { _ in try resampler.convert(sine(frames: 4_800)) }
        #expect((output.max() ?? 0) > 0.4)
    }

    private func sine(frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: stereo48k, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(stereo48k.channelCount) {
            let data = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                data[frame] = 0.5 * sin(2 * .pi * 440 * Float(frame) / 48_000)
            }
        }
        return buffer
    }
}
