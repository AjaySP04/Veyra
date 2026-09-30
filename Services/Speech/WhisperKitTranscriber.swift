import Foundation
import WhisperKit

final class WhisperKitTranscriber: Transcribing {
    private static let decodingOptions = DecodingOptions(
        detectLanguage: true,
        skipSpecialTokens: true,
        withoutTimestamps: true,
        chunkingStrategy: .vad
    )

    private let variant: String
    private let downloadBase: URL
    private let cache: ModelFolderCache
    private var whisperKit: WhisperKit?

    init(
        variant: String = "large-v3-v20240930_turbo",
        downloadBase: URL = .applicationSupportDirectory.appending(path: "Veyra/Models"),
        defaults: UserDefaults = .standard
    ) {
        self.variant = variant
        self.downloadBase = downloadBase
        self.cache = ModelFolderCache(defaults: defaults, key: "modelFolder.\(variant)")
    }

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        let folder = try await modelFolder(progress: progress)
        do {
            whisperKit = try await WhisperKit(WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: downloadBase,
                verbose: false,
                logLevel: .error,
                load: true,
                download: false
            ))
        } catch {
            cache.clear()
            throw error
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: Self.decodingOptions)
        return TranscriptCleaner.clean(results.map(\.text).joined(separator: " "))
    }

    private func modelFolder(progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        if let cached = cache.folder { return cached }
        let folder = try await WhisperKit.download(variant: variant, downloadBase: downloadBase) { update in
            let fraction = update.fractionCompleted
            Task { @MainActor in progress(fraction) }
        }
        cache.store(folder)
        return folder
    }
}
