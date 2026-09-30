import AVFoundation

nonisolated final class AudioResampler: @unchecked Sendable {
    private let converter: AVAudioConverter

    init(inputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: AudioFormat.transcription) else {
            throw AudioCaptureError.unsupportedFormat
        }
        converter.downmix = true
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let ratio = AudioFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: AudioFormat.transcription, frameCapacity: capacity) else {
            throw AudioCaptureError.unsupportedFormat
        }

        nonisolated(unsafe) var isConsumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard !isConsumed else {
                status.pointee = .noDataNow
                return nil
            }
            isConsumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }

        guard let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
