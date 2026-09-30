import AVFoundation
import Testing
@testable import Veyra

struct AudioResamplerTests {
    private let stereo48k = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private let voiceProcessed48k = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        interleaved: false,
        channelLayout: AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 9)!
    )

    @Test func convertsStereo48kToMono16k() throws {
        let resampler = try AudioResampler(inputFormat: stereo48k)
        let counts = try (0..<10).map { _ in try resampler.convert(sine(format: stereo48k, frames: 4_800)).count }
        #expect(counts.dropFirst().allSatisfy { $0 == 1_600 })
        #expect(counts[0] >= 1_280)
    }

    @Test func preservesSignal() throws {
        let resampler = try AudioResampler(inputFormat: stereo48k)
        let output = try (0..<3).flatMap { _ in try resampler.convert(sine(format: stereo48k, frames: 4_800)) }
        #expect((output.max() ?? 0) > 0.4)
    }

    @Test func keepsVoiceProcessedChannelAtFullLevel() throws {
        let resampler = try AudioResampler(inputFormat: voiceProcessed48k)
        let output = try (0..<3).flatMap { _ in
            try resampler.convert(sine(format: voiceProcessed48k, frames: 4_800, voicedChannels: [0]))
        }
        #expect((output.max() ?? 0) > 0.4)
    }

    private func sine(format: AVAudioFormat, frames: AVAudioFrameCount, voicedChannels: Set<Int>? = nil) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            let amplitude: Float = voicedChannels?.contains(channel) ?? true ? 0.5 : 0
            let data = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                data[frame] = amplitude * sin(2 * .pi * 440 * Float(frame) / 48_000)
            }
        }
        return buffer
    }
}
