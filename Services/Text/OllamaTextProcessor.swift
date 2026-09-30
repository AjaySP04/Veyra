import Foundation
import os

struct OllamaTextProcessor: TextProcessing {
    private let client: ChatCompleting
    private let models: [CleanupModel]

    init(client: ChatCompleting, models: [CleanupModel] = CleanupModel.chain) {
        self.client = client
        self.models = models
    }

    func process(_ text: String, mode: DictationMode) async throws -> String {
        mode.finalize(await cleaned(text, mode: mode))
    }

    private func cleaned(_ text: String, mode: DictationMode) async -> String {
        guard !CleanupGuard.words(in: text).isEmpty else { return text }
        for model in models {
            if let cleaned = await cleanup(text, mode: mode, with: model) { return cleaned }
        }
        Logger.cleanup.info("No cleanup model available, pasting raw transcript")
        return text
    }

    private func cleanup(_ text: String, mode: DictationMode, with model: CleanupModel) async -> String? {
        let start = ContinuousClock.now
        do {
            let reply = CleanupPrompt.reply(from: try await client.complete(request(for: text, mode: mode, with: model)))
            guard CleanupGuard.accepts(original: text, cleaned: reply) else {
                Logger.cleanup.info("\(model.name, privacy: .public) reply rejected by guard")
                return nil
            }
            let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
            Logger.cleanup.info("\(model.name, privacy: .public) cleaned \(text.count) → \(reply.count) characters in \(milliseconds) ms")
            return reply
        } catch {
            Logger.cleanup.info("\(model.name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            if (error as? URLError)?.code == .timedOut { client.warmUp(model.name) }
            return nil
        }
    }

    private func request(for text: String, mode: DictationMode, with model: CleanupModel) -> ChatRequest {
        ChatRequest(
            model: model.name,
            system: CleanupPrompt.system(for: mode),
            user: CleanupPrompt.userMessage(for: text),
            timeout: model.timeout(forWordCount: CleanupGuard.words(in: text).count)
        )
    }
}
