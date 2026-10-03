import Testing
@testable import Veyra

@MainActor
struct AgentRunnerTests {
    private let caller = FakeToolCaller()
    private let tool = FakeTool()
    private let openSlack = ToolReply.call(ToolCall(name: "open", arguments: ["kind": "app", "target": "Slack"]))
    private let local = "gemma4:latest"
    private let cloud = "gemma4:cloud"

    private var runner: AgentRunner { AgentRunner(caller: caller, registry: ToolRegistry([tool])) }

    @Test func performsThePreparedAction() async {
        caller.replies[local] = .success(openSlack)
        #expect(await runner.run("Open Slack.") == .done("Opened Slack"))
        #expect(tool.preparedArguments == [["kind": "app", "target": "Slack"]])
        #expect(tool.performCount == 1)
        #expect(caller.requests.map(\.model) == [local])
    }

    @Test func sendsTranscriptToolsAndPrompt() async {
        caller.replies[local] = .success(openSlack)
        _ = await runner.run("Open Slack.")
        let request = caller.requests[0]
        #expect(request.system == AgentRunner.systemPrompt)
        #expect(request.user == "<request>Open Slack.</request>")
        #expect(request.tools == [tool.definition])
    }

    @Test func textReplyIsUnsupportedWithoutTryingCloud() async {
        caller.replies[local] = .success(.text("unsupported"))
        caller.replies[cloud] = .success(openSlack)
        #expect(await runner.run("what's the weather") == .failed("I can open things, rewrite text, write commands and send messages for now"))
        #expect(caller.requests.map(\.model) == [local])
        #expect(tool.performCount == 0)
    }

    @Test func localErrorFallsBackToCloud() async {
        caller.replies[cloud] = .success(openSlack)
        #expect(await runner.run("Open Slack.") == .done("Opened Slack"))
        #expect(caller.requests.map(\.model) == [local, cloud])
    }

    @Test func unknownToolFallsBackToCloud() async {
        caller.replies[local] = .success(.call(ToolCall(name: "launch", arguments: [:])))
        caller.replies[cloud] = .success(openSlack)
        #expect(await runner.run("Open Slack.") == .done("Opened Slack"))
    }

    @Test func invalidArgumentsFallBackToCloud() async {
        tool.prepareError = AgentError.invalidArguments
        caller.replies[local] = .success(openSlack)
        caller.replies[cloud] = .success(openSlack)
        #expect(await runner.run("Open Slack.") == .failed("Didn't catch what to do"))
        #expect(caller.requests.map(\.model) == [local, cloud])
    }

    @Test func unknownToolEverywhereIsUnsupported() async {
        caller.replies[local] = .success(.call(ToolCall(name: "launch", arguments: [:])))
        caller.replies[cloud] = .success(.call(ToolCall(name: "launch", arguments: [:])))
        #expect(await runner.run("Open Slack.") == .failed("I can open things, rewrite text, write commands and send messages for now"))
    }

    @Test func malformedThenUnreachableKeepsTheMalformedMessage() async {
        caller.replies[local] = .success(.call(ToolCall(name: "launch", arguments: [:])))
        #expect(await runner.run("Open Slack.") == .failed("I can open things, rewrite text, write commands and send messages for now"))
    }

    @Test func noModelReachableNeedsOllama() async {
        #expect(await runner.run("Open Slack.") == .failed("Actions need Ollama running"))
        #expect(tool.performCount == 0)
    }

    @Test func notFoundIsReportedWithoutRetrying() async {
        tool.prepareError = AgentError.noApp("Slak")
        caller.replies[local] = .success(openSlack)
        caller.replies[cloud] = .success(openSlack)
        #expect(await runner.run("Open Slak.") == .failed("No app called “Slak”"))
        #expect(caller.requests.map(\.model) == [local])
        #expect(tool.performCount == 0)
    }

    @Test func performFailureIsReported() async {
        tool.performError = TestError()
        caller.replies[local] = .success(openSlack)
        #expect(await runner.run("Open Slack.") == .failed("Couldn't open Slack"))
        #expect(tool.performCount == 1)
    }

    @Test(arguments: [
        (AgentError.unsupported, "I can open things, rewrite text, write commands and send messages for now"),
        (.invalidArguments, "Didn't catch what to do"),
        (.unavailable, "Actions need Ollama running"),
        (.noApp("Foo"), "No app called “Foo”"),
        (.noFile("resume"), "No file matching “resume”"),
        (.badAddress, "Can't open that address"),
        (.noSelection, "Select some text first"),
        (.tooLong, "That's too much text to rewrite"),
        (.rewriteFailed, "Couldn't rewrite that"),
        (.appChanged, "Cancelled because the app changed"),
    ])
    func errorMessages(error: AgentError, message: String) {
        #expect(error.message == message)
    }

    @Test func passesContextToTheTool() async {
        caller.replies[local] = .success(openSlack)
        let context = ToolContext(mode: .chat, bundleIdentifier: "com.tinyspeck.slackmacgap", lastInsertion: LastInsertion(text: "hi", bundleIdentifier: "com.tinyspeck.slackmacgap"))
        _ = await runner.run("Open Slack.", in: context)
        #expect(tool.contexts == [context])
    }

    @Test func returnsTheActionsInsertion() async {
        tool.insertion = LastInsertion(text: "Hello.", bundleIdentifier: "com.apple.Notes")
        caller.replies[local] = .success(openSlack)
        #expect(await runner.run("Open Slack.") == .done("Opened Slack", insertion: tool.insertion))
    }

    @Test func performAgentErrorMessageIsShown() async {
        tool.performError = AgentError.appChanged
        caller.replies[local] = .success(openSlack)
        #expect(await runner.run("Open Slack.") == .failed("Cancelled because the app changed"))
    }

    @Test func confirmToolDraftsThenAwaitsConfirmation() async throws {
        var confirmed = 0
        let confirmation = Confirmation(done: "Sent", failure: "Couldn't send") { confirmed += 1 }
        tool.risk = .confirm
        tool.confirmation = confirmation
        tool.insertion = LastInsertion(text: "Sounds good", bundleIdentifier: "com.tinyspeck.slackmacgap")
        caller.replies[local] = .success(openSlack)
        let outcome = await runner.run("reply sounds good")
        #expect(outcome == .awaiting("Opened Slack", insertion: tool.insertion, confirmation: confirmation))
        #expect(tool.performCount == 1)
        #expect(confirmed == 0)
        guard case .awaiting(_, _, let pending) = outcome else { return }
        try await pending.perform()
        #expect(confirmed == 1)
    }

    @Test func confirmToolWithoutAConfirmationIsRefused() async {
        tool.risk = .confirm
        caller.replies[local] = .success(openSlack)
        #expect(await runner.run("reply sounds good") == .failed("Couldn't open Slack"))
        #expect(tool.performCount == 0)
    }

    @Test func confirmToolDraftFailureIsReported() async {
        tool.risk = .confirm
        tool.confirmation = Confirmation(done: "Sent", failure: "Couldn't send") {}
        tool.performError = AgentError.interrupted
        caller.replies[local] = .success(openSlack)
        #expect(await runner.run("reply sounds good") == .failed("Cancelled because you typed"))
    }

    @Test func immediateToolIgnoresAConfirmation() async {
        tool.confirmation = Confirmation(done: "Sent", failure: "Couldn't send") {}
        caller.replies[local] = .success(openSlack)
        #expect(await runner.run("Open Slack.") == .done("Opened Slack"))
    }

    @Test func sendMessages() {
        #expect(AgentError.notMessaging.message == "Open a chat or email first")
        #expect(AgentError.messageTooLong.message == "That message is too long")
    }

    @Test func newRewriteMessages() {
        #expect(AgentError.interrupted.message == "Cancelled because you typed")
        #expect(AgentError.readOnly.message == "That text can't be edited")
    }
}
