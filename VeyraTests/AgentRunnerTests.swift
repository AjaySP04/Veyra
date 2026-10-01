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
        #expect(await runner.run("what's the weather") == .failed("I can only open apps, websites, folders and files for now"))
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
        #expect(await runner.run("Open Slack.") == .failed("Didn't catch what to open"))
        #expect(caller.requests.map(\.model) == [local, cloud])
    }

    @Test func unknownToolEverywhereIsUnsupported() async {
        caller.replies[local] = .success(.call(ToolCall(name: "launch", arguments: [:])))
        caller.replies[cloud] = .success(.call(ToolCall(name: "launch", arguments: [:])))
        #expect(await runner.run("Open Slack.") == .failed("I can only open apps, websites, folders and files for now"))
    }

    @Test func malformedThenUnreachableKeepsTheMalformedMessage() async {
        caller.replies[local] = .success(.call(ToolCall(name: "launch", arguments: [:])))
        #expect(await runner.run("Open Slack.") == .failed("I can only open apps, websites, folders and files for now"))
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
        (AgentError.unsupported, "I can only open apps, websites, folders and files for now"),
        (.invalidArguments, "Didn't catch what to open"),
        (.unavailable, "Actions need Ollama running"),
        (.noApp("Foo"), "No app called “Foo”"),
        (.noFile("resume"), "No file matching “resume”"),
        (.badAddress, "Can't open that address"),
    ])
    func errorMessages(error: AgentError, message: String) {
        #expect(error.message == message)
    }
}
