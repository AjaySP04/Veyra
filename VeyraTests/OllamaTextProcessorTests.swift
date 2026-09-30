import Foundation
import Testing
@testable import Veyra

@MainActor
struct OllamaTextProcessorTests {
    private let transcript = "hey team uh payment integration is done"
    private let models = [
        CleanupModel(name: "local", baseTimeout: .seconds(6), timeoutPerWord: .zero),
        CleanupModel(name: "cloud", baseTimeout: .seconds(3), timeoutPerWord: .zero),
    ]
    private let client = FakeChatCompleter()

    private func process(_ text: String, mode: DictationMode = .standard) async throws -> String {
        try await OllamaTextProcessor(client: client, models: models).process(text, mode: mode)
    }

    @Test func defaultChainPrefersLocalThenCloud() {
        #expect(CleanupModel.chain == [
            CleanupModel(name: "gemma4:latest", baseTimeout: .seconds(6), timeoutPerWord: .milliseconds(30)),
            CleanupModel(name: "gemma4:cloud", baseTimeout: .seconds(3), timeoutPerWord: .milliseconds(10)),
        ])
    }

    @Test func firstAcceptedReplyWins() async throws {
        client.replies = ["local": .success("Hey team, payment integration is done."), "cloud": .success("unused")]
        #expect(try await process(transcript) == "Hey team, payment integration is done.")
        #expect(client.requests.map(\.model) == ["local"])
    }

    @Test func errorFallsThroughToNextModel() async throws {
        client.replies = ["local": .failure(ChatError.badStatus(404)), "cloud": .success("Hey team, payment integration is done.")]
        #expect(try await process(transcript) == "Hey team, payment integration is done.")
        #expect(client.requests.map(\.model) == ["local", "cloud"])
    }

    @Test func rejectedReplyFallsThroughToNextModel() async throws {
        client.replies = [
            "local": .success("Sure! Here is a summary of your update."),
            "cloud": .success("Hey team, payment integration is done."),
        ]
        #expect(try await process(transcript) == "Hey team, payment integration is done.")
    }

    @Test func returnsRawTranscriptWhenEveryModelFails() async throws {
        #expect(try await process(transcript) == transcript)
        #expect(client.requests.map(\.model) == ["local", "cloud"])
    }

    @Test func cancellationReturnsRawTranscript() async throws {
        client.replies = ["local": .failure(CancellationError()), "cloud": .failure(CancellationError())]
        #expect(try await process(transcript) == transcript)
    }

    @Test func unwrapsTaggedReply() async throws {
        client.replies = ["local": .success("<transcript>\nHey team, payment integration is done.\n</transcript>")]
        #expect(try await process(transcript) == "Hey team, payment integration is done.")
    }

    @Test func eachModelGetsItsOwnNameAndTimeout() async throws {
        _ = try await process(transcript)
        #expect(client.requests == [
            ChatRequest(model: "local", system: CleanupPrompt.system(for: .standard), user: CleanupPrompt.userMessage(for: transcript), timeout: .seconds(6)),
            ChatRequest(model: "cloud", system: CleanupPrompt.system(for: .standard), user: CleanupPrompt.userMessage(for: transcript), timeout: .seconds(3)),
        ])
    }

    @Test(arguments: ["", "   ", " … "])
    func textWithoutWordsSkipsCleanup(text: String) async throws {
        #expect(try await process(text) == text)
        #expect(client.requests.isEmpty)
    }

    @Test func timeoutGrowsWithTranscriptLength() async throws {
        let model = CleanupModel(name: "local", baseTimeout: .seconds(6), timeoutPerWord: .milliseconds(30))
        let longTranscript = Array(repeating: "word", count: 300).joined(separator: " ")
        _ = try await OllamaTextProcessor(client: client, models: [model]).process(longTranscript, mode: .standard)
        #expect(client.requests.map(\.timeout) == [.seconds(15)])
    }

    @Test func timedOutModelIsWarmedUpInBackground() async throws {
        client.replies = ["local": .failure(URLError(.timedOut))]
        _ = try await process(transcript)
        #expect(client.warmedUpModels == ["local"])
    }

    @Test func otherFailuresDoNotWarmUp() async throws {
        client.replies = ["local": .failure(ChatError.badStatus(404)), "cloud": .failure(URLError(.cannotConnectToHost))]
        _ = try await process(transcript)
        #expect(client.warmedUpModels.isEmpty)
    }

    @Test func systemPromptFollowsMode() async throws {
        _ = try await process(transcript, mode: .email)
        #expect(client.requests.map(\.system) == Array(repeating: CleanupPrompt.system(for: .email), count: 2))
    }

    @Test func terminalReplyIsFlattened() async throws {
        client.replies = ["local": .success("Hey team:\n- payment integration is done.")]
        #expect(try await process(transcript, mode: .terminal) == "Hey team: payment integration is done.")
    }

    @Test func terminalRawFallbackIsFlattened() async throws {
        #expect(try await process("first line\nsecond line", mode: .terminal) == "first line; second line")
    }

    @Test func emailKeepsMultilineReply() async throws {
        client.replies = ["local": .success("Hey team,\n\nPayment integration is done.")]
        #expect(try await process(transcript, mode: .email) == "Hey team,\n\nPayment integration is done.")
    }
}
