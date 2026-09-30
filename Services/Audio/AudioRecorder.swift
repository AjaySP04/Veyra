import AVFoundation

final class AudioRecorder: AudioCapturing {
    var levelHandler: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let buffer = SampleBuffer()

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }

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
        return buffer.drain()
    }

    private nonisolated static func makeTap(
        resampler: AudioResampler,
        buffer: SampleBuffer,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { pcm, _ in
            guard let samples = try? resampler.convert(pcm), !samples.isEmpty else { return }
            buffer.append(samples)
            onLevel(AudioLevel.normalized(samples))
        }
    }
}
