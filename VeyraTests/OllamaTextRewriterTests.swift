import Testing
@testable import Veyra

@MainActor
struct OllamaTextRewriterTests {
    private let client = FakeChatCompleter()
    private var rewriter: OllamaTextRewriter { OllamaTextRewriter(client: client) }

    @Test func sendsInstructionAndText() async throws {
        client.replies["gemma4:latest"] = .success("Hello there.")
        _ = try await rewriter.rewrite("hey", instruction: "more formal")
        let request = try #require(client.requests.first)
        #expect(request.system == RewritePrompt.system)
        #expect(request.user == "<instruction>more formal</instruction>\n<text>\nhey\n</text>")
    }

    @Test func stripsEchoedTags() async throws {
        client.replies["gemma4:latest"] = .success("<text>\nHello there.\n</text>")
        #expect(try await rewriter.rewrite("hey", instruction: "more formal") == "Hello there.")
    }

    @Test func localErrorFallsBackToCloud() async throws {
        client.replies["gemma4:cloud"] = .success("Hello there.")
        #expect(try await rewriter.rewrite("hey", instruction: "more formal") == "Hello there.")
    }

    @Test func emptyLocalReplyFallsBackToCloud() async throws {
        client.replies["gemma4:latest"] = .success("  ")
        client.replies["gemma4:cloud"] = .success("Hello there.")
        #expect(try await rewriter.rewrite("hey", instruction: "more formal") == "Hello there.")
    }

    @Test func everyReplyEmptyFails() async {
        client.replies["gemma4:latest"] = .success("")
        client.replies["gemma4:cloud"] = .success("")
        await #expect(throws: AgentError.rewriteFailed) { try await rewriter.rewrite("hey", instruction: "x") }
    }

    @Test func noModelReachableIsUnavailable() async {
        await #expect(throws: AgentError.unavailable) { try await rewriter.rewrite("hey", instruction: "x") }
    }
}
