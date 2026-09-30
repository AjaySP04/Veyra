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
}
