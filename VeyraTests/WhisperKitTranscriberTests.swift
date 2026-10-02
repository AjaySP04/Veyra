import Testing
import WhisperKit
@testable import Veyra

@MainActor
struct WhisperKitTranscriberTests {
    @Test func decodingForcesConfiguredLanguage() {
        let options = WhisperKitTranscriber.decodingOptions(language: "en")
        #expect(options.language == "en")
        #expect(!options.detectLanguage)
        #expect(options.usePrefillPrompt)
    }

    @Test func decodingDropsNonSpeechTokensAndChunksLongAudio() {
        let options = WhisperKitTranscriber.decodingOptions(language: "en")
        #expect(options.skipSpecialTokens)
        #expect(options.withoutTimestamps)
        #expect(options.chunkingStrategy == .vad)
    }

    @Test func dropsSegmentsWhisperJudgesSilent() {
        let segments = [TranscriptionSegment(text: " Thank you.", avgLogprob: -0.2, noSpeechProb: 0.9)]
        #expect(WhisperKitTranscriber.speechText(from: segments) == "")
    }

    @Test func keepsSpeechSegmentsInOrder() {
        let segments = [
            TranscriptionSegment(text: " Hello", noSpeechProb: 0.1),
            TranscriptionSegment(text: " [MUSIC]", noSpeechProb: 0.95),
            TranscriptionSegment(text: " world.", noSpeechProb: 0.3),
        ]
        #expect(WhisperKitTranscriber.speechText(from: segments) == "Hello world.")
    }

    @Test func padsShortClipsPastWhisperKitsEndClip() {
        let clip = [Float](repeating: 0.5, count: 12_560)
        let padded = WhisperKitTranscriber.padded(clip)
        #expect(padded.count == 32_000)
        #expect(Array(padded.prefix(12_560)) == clip)
        #expect(padded.dropFirst(12_560).allSatisfy { $0 == 0 })
    }

    @Test func leavesLongClipsAlone() {
        let clip = [Float](repeating: 0.5, count: 48_000)
        #expect(WhisperKitTranscriber.padded(clip) == clip)
    }
}
