import Foundation

protocol Transcribing {
    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? { "Speech model is not loaded" }
}
