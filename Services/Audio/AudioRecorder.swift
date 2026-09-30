import AVFoundation
import os

final class AudioRecorder: AudioCapturing {
    var levelHandler: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let buffer = SampleBuffer()

    func start() throws {
        let input = engine.inputNode
        enableVoiceProcessing(on: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }
        Logger.audio.info("Input \(format.sampleRate) Hz, \(format.channelCount) ch, voice processing \(input.isVoiceProcessingEnabled)")

        let tap = Self.makeTap(resampler: try AudioResampler(inputFormat: format), buffer: buffer) { [weak self] level in
            Task { @MainActor in self?.levelHandler?(level) }
        }
        input.installTap(onBus: 0, bufferSize: 4_096, format: format, block: tap)
        engine.prepare()

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let samples = buffer.drain()
        Logger.audio.info("Captured \(samples.count) samples")
        return samples
    }

    private func enableVoiceProcessing(on input: AVAudioInputNode) {
        guard !input.isVoiceProcessingEnabled, (try? input.setVoiceProcessingEnabled(true)) != nil else { return }
        input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
    }

    private nonisolated static func makeTap(
        resampler: AudioResampler,
        buffer: SampleBuffer,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { pcm, _ in
            let samples: [Float]
            do {
                samples = try resampler.convert(pcm)
            } catch {
                return Logger.audio.error("Conversion failed: \(error.localizedDescription, privacy: .public)")
            }
            guard !samples.isEmpty else { return }
            buffer.append(samples)
            onLevel(AudioLevel.normalized(samples))
        }
    }
}
