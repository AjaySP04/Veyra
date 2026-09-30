import Foundation
import os

struct OllamaTextProcessor: TextProcessing {
    private let client: ChatCompleting
    private let models: [CleanupModel]

    init(client: ChatCompleting, models: [CleanupModel] = CleanupModel.chain) {
        self.client = client
        self.models = models
    }

    func process(_ text: String) async throws -> String {
        guard !CleanupGuard.words(in: text).isEmpty else { return text }
        for model in models {
            if let cleaned = await cleanup(text, with: model) { return cleaned }
        }
        Logger.cleanup.info("No cleanup model available, pasting raw transcript")
        return text
    }

    private func cleanup(_ text: String, with model: CleanupModel) async -> String? {
        let start = ContinuousClock.now
        do {
            let reply = CleanupPrompt.reply(from: try await client.complete(request(for: text, with: model)))
            guard CleanupGuard.accepts(original: text, cleaned: reply) else {
                Logger.cleanup.info("\(model.name, privacy: .public) reply rejected by guard")
                return nil
            }
            let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
            Logger.cleanup.info("\(model.name, privacy: .public) cleaned \(text.count) → \(reply.count) characters in \(milliseconds) ms")
            return reply
        } catch {
            Logger.cleanup.info("\(model.name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func request(for text: String, with model: CleanupModel) -> ChatRequest {
        ChatRequest(
            model: model.name,
            system: CleanupPrompt.system,
            user: CleanupPrompt.userMessage(for: text),
            timeout: model.timeout
        )
    }
}
