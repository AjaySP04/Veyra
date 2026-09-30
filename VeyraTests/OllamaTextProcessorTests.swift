import Testing
@testable import Veyra

@MainActor
struct OllamaTextProcessorTests {
    private let transcript = "hey team uh payment integration is done"
    private let models = [
        CleanupModel(name: "local", timeout: .seconds(6)),
        CleanupModel(name: "cloud", timeout: .seconds(3)),
    ]
    private let client = FakeChatCompleter()

    private func process(_ text: String) async throws -> String {
        try await OllamaTextProcessor(client: client, models: models).process(text)
    }

    @Test func defaultChainPrefersLocalThenCloud() {
        #expect(CleanupModel.chain == [
            CleanupModel(name: "gemma4:latest", timeout: .seconds(6)),
            CleanupModel(name: "gemma4:cloud", timeout: .seconds(3)),
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
            ChatRequest(model: "local", system: CleanupPrompt.system, user: CleanupPrompt.userMessage(for: transcript), timeout: .seconds(6)),
            ChatRequest(model: "cloud", system: CleanupPrompt.system, user: CleanupPrompt.userMessage(for: transcript), timeout: .seconds(3)),
        ])
    }

    @Test(arguments: ["", "   ", " … "])
    func textWithoutWordsSkipsCleanup(text: String) async throws {
        #expect(try await process(text) == text)
        #expect(client.requests.isEmpty)
    }
}
