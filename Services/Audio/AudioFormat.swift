import AVFoundation

nonisolated enum AudioFormat {
    static let sampleRate: Double = 16_000
    static let transcription = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!
}
