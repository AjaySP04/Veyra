# Agent Foundation and "Open" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Holding Fn + Control and saying "open Slack / github dot com / my downloads / my resume" opens it, through local-first LLM tool calling with Swift-side resolution.

**Architecture:**
- A new `Gesture` on the hotkey routes action-mode transcripts to `AgentRunner`.
- `AgentRunner` asks `gemma4:latest`, then `gemma4:cloud`, for one tool call over Ollama's native `tools` API.
- The `open` tool's `prepare` step resolves the call's `target` against real apps, standard folders, Spotlight results or a validated URL. Only then does `perform()` open it.
- All matching rules are pure functions. AppKit and Spotlight sit behind small protocols.

**Tech Stack:** Swift 5 mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, AppKit (`NSWorkspace`, `NSMetadataQuery`), Ollama `/api/chat` with `tools`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-01-agent-open-design.md`

## Global Constraints

- Plain Fn behaviour, including Phase 7 commands, must not change. Action-mode speech never reaches `TextProcessing`, `TextInserting`, `Intent` or `KeystrokeSending`.
- The model's `target` is a search term only. Open only resolved app bundles, standard folders, Spotlight results, and `http`/`https` URLs whose host contains a dot.
- Model chain: `CleanupModel.chain` (`gemma4:latest`, then `gemma4:cloud`). Cloud is tried only after an error, a timeout or a malformed call. A text reply stands.
- Copy these messages verbatim:
  - "Opened <name>"
  - " · N other matches" (" · 1 other match" for one)
  - "I can only open apps, websites, folders and files for now"
  - "Didn't catch what to open"
  - "No app called “<target>”"
  - "No file matching “<target>”"
  - "Can't open that address"
  - "Actions need Ollama running"
  - "Couldn't open <name>"
- Logs (`Logger.agent`) record the tool name, the kind (only when it is one of app, website, folder or file), the outcome, the model and the milliseconds. Never log the transcript, target, app name, host or file name.
- New files go in the synchronized folders (`App/`, `Features/`, `Services/`, `VeyraTests/`). Do not edit `project.pbxproj`.
- Test command: `xcodebuild test -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS'`. For one suite, add `-only-testing:VeyraTests/<Suite>`.

## Review Focus

1. **Holding Control without Fn, or pressing Control+letter shortcuts while Fn is up.** These must never start a recording or clear "scratch that" differently than today. Pinned in Task 1.
2. **Whisper splitting letters** ("V S code") must still resolve to Visual Studio Code. Pinned in Task 4.
3. **A trailing period or a capitalized domain** from the model ("YouTube.com.") must still open https://youtube.com. Pinned in Task 4.
4. **A local malformed call followed by a cloud network error** must report the malformed message, not "Actions need Ollama running". Pinned in Task 3.
5. **An action right after a dictation** must clear the stored "scratch that" insertion, because focus moves to the opened app. Pinned in Task 6.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `Services/System/HotkeyMonitoring.swift` | Modify | `Gesture`, `HotkeyEvent.pressed(Gesture)` |
| `Services/System/FnKeyTracker.swift`, `Services/System/FnKeyMonitor.swift` | Modify | Control tracked separately. Fn+⌃ means `.act` |
| `Services/Agent/ToolCalling.swift` | Create | `ToolParameter`, `ToolDefinition`, `ToolRequest`, `ToolCall`, `ToolReply`, `ToolCalling` |
| `Services/Text/OllamaClient.swift` | Modify | `callTool(_:)`, encoding `tools`, decoding `tool_calls` |
| `Features/Agent/Tool.swift` | Create | `Tool`, `ToolRisk`, `PreparedAction` |
| `Features/Agent/ToolRegistry.swift` | Create | Tool lookup and definitions |
| `Features/Agent/AgentError.swift` | Create | User-facing errors |
| `Features/Agent/AgentRunner.swift` | Create | `AgentOutcome`, `AgentRunning`, `AgentRunner` |
| `Features/Agent/Open/AppResolver.swift`, `WebsiteResolver.swift`, `FolderResolver.swift`, `FileSearcher.swift` | Create | Pure resolution rules |
| `Features/Agent/Open/OpenTool.swift` | Create | The `open` tool |
| `Services/System/WorkspaceOpening.swift` | Create | `WorkspaceOpening`, `NSWorkspaceOpener`, `AppListing`, `InstalledAppDirectory` |
| `Services/System/SpotlightFileSearcher.swift` | Create | `FileSearching`, `SpotlightFileSearcher` |
| `App/Logger+Veyra.swift` | Modify | `Logger.agent` |
| `Features/Dictation/DictationCoordinator.swift`, `DictationState.swift`, `DictationState+Presentation.swift`, `RecordingOverlay.swift` | Modify | Action routing, `.acting` and `.acted`, overlay |
| `App/AppDependencies.swift` | Modify | Wiring |
| `VeyraTests/*` | Create or modify | Suites below, plus fakes |
| `README.md`, `docs/VISION.md`, `AGENTS.md` | Modify | Docs |

---

### Task 1: Fn + Control gesture

**Files:**
- Modify: `Services/System/HotkeyMonitoring.swift`, `Services/System/FnKeyTracker.swift`, `Services/System/FnKeyMonitor.swift`, `Features/Dictation/DictationCoordinator.swift`
- Test: `VeyraTests/FnKeyTrackerTests.swift`, plus a mechanical `.pressed` → `.pressed(.dictate)` change in `VeyraTests/DictationCoordinatorTests.swift`

**Interfaces:**
- Produces:
  - `enum Gesture: Equatable { case dictate, act }`
  - `HotkeyEvent.pressed(Gesture)`
  - `KeyInput.flagsChanged(fn: Bool, control: Bool = false, otherModifiers: Bool = false)`
  - `DictationCoordinator.gesture: Gesture` (observable, `private(set)`)

- [ ] **Step 1: Update the existing tests mechanically.**

```bash
perl -pi -e 's/\.pressed(?!\()/.pressed(.dictate)/g' VeyraTests/FnKeyTrackerTests.swift VeyraTests/DictationCoordinatorTests.swift
```

- [ ] **Step 2: Add the failing tests to `FnKeyTrackerTests`.**

```swift
    private let controlFnDown = KeyInput.flagsChanged(fn: true, control: true)
    private let controlOnly = KeyInput.flagsChanged(fn: false, control: true)

    @Test func controlThenFnStartsAnAction() {
        #expect(events([controlOnly, controlFnDown, fnUp]) == [.pressed(.act), .released])
    }

    @Test func releasingControlDuringAnActionKeepsIt() {
        #expect(events([controlFnDown, fnDown, fnUp]) == [.pressed(.act), .released])
    }

    @Test func addingControlDuringDictationCancels() {
        #expect(events([fnDown, controlFnDown, fnUp]) == [.pressed(.dictate), .cancelled])
    }

    @Test func controlWithAnotherModifierDoesNotPress() {
        #expect(events([.flagsChanged(fn: true, control: true, otherModifiers: true), fnUp]).isEmpty)
    }

    @Test func controlAloneDoesNothing() {
        #expect(events([controlOnly, .flagsChanged(fn: false)]).isEmpty)
    }
```

- [ ] **Step 3: Run `FnKeyTrackerTests`.** Expected: build failure, because `Gesture` and `control:` don't exist.

- [ ] **Step 4: In `HotkeyMonitoring.swift`, add `Gesture` and change the press case.**

```swift
enum Gesture: Equatable {
    case dictate
    case act
}

enum HotkeyEvent: Equatable {
    case pressed(Gesture)
    case released
    case cancelled
    case userInput
}
```

- [ ] **Step 5: Replace `Services/System/FnKeyTracker.swift`.**

```swift
enum KeyInput: Equatable {
    case flagsChanged(fn: Bool, control: Bool = false, otherModifiers: Bool = false)
    case keyDown
    case mouseDown
}

struct FnKeyTracker {
    private var held: Gesture?
    private var isCancelled = false

    mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fn: true, control: let control, otherModifiers: false) where held == nil:
            let gesture: Gesture = control ? .act : .dictate
            held = gesture
            isCancelled = false
            return .pressed(gesture)
        case .flagsChanged(fn: false, control: _, otherModifiers: _) where held != nil:
            held = nil
            return isCancelled ? nil : .released
        case .flagsChanged(fn: true, control: _, otherModifiers: true) where held != nil,
             .flagsChanged(fn: true, control: true, otherModifiers: _) where held == .dictate,
             .keyDown where held != nil:
            return cancel()
        case .keyDown where held == nil, .mouseDown where held == nil:
            return .userInput
        default:
            return nil
        }
    }

    private mutating func cancel() -> HotkeyEvent? {
        guard !isCancelled else { return nil }
        isCancelled = true
        return .cancelled
    }
}
```

- [ ] **Step 6: In `FnKeyMonitor.swift`, split out Control.** In the `.flagsChanged` branch, use:

```swift
            self = .flagsChanged(
                fn: flags.contains(.function),
                control: flags.contains(.control),
                otherModifiers: !flags.isDisjoint(with: [.shift, .option, .command])
            )
```

- [ ] **Step 7: Make the coordinator compile, with no behaviour change yet.** In `DictationCoordinator.swift`:
  - Add `private(set) var gesture: Gesture = .dictate` after `state`.
  - Change `case (.pressed, .idle): beginRecording()` to `case (.pressed(let gesture), .idle): beginRecording(gesture)`.
  - Change `beginRecording()` to `beginRecording(_ gesture: Gesture)`, and set `self.gesture = gesture` right after `state = .recording(level: 0)`.

- [ ] **Step 8: Run the full suite.** Expected: all pass.

- [ ] **Step 9: Commit.** `git add -A && git commit -m "Start an action with Fn + Control"`

---

### Task 2: Tool calling over Ollama

**Files:**
- Create: `Services/Agent/ToolCalling.swift`
- Modify: `Services/Text/OllamaClient.swift`
- Test: `VeyraTests/OllamaClientTests.swift`

**Interfaces:**
- Produces:
  - `struct ToolParameter: Equatable { let name: String; let description: String; let allowed: [String]? }` (every parameter is a required string)
  - `struct ToolDefinition: Equatable { let name: String; let description: String; let parameters: [ToolParameter] }`
  - `struct ToolRequest: Equatable { let model: String; let system: String; let user: String; let tools: [ToolDefinition]; let timeout: Duration }`
  - `struct ToolCall: Equatable { let name: String; let arguments: [String: String] }`
  - `enum ToolReply: Equatable { case call(ToolCall); case text(String) }`
  - `protocol ToolCalling { func callTool(_ request: ToolRequest) async throws -> ToolReply }`
  - `OllamaClient: ToolCalling`, with `func urlRequest(for request: ToolRequest) throws -> URLRequest`

- [ ] **Step 1: Write the failing tests.** Append to `OllamaClientTests`:

```swift
    private let toolRequest = ToolRequest(
        model: "gemma4:latest", system: "sys", user: "open slack",
        tools: [ToolDefinition(name: "open", description: "Open things", parameters: [
            ToolParameter(name: "kind", description: "What", allowed: ["app", "file"]),
            ToolParameter(name: "target", description: "Name", allowed: nil),
        ])],
        timeout: .seconds(6)
    )

    @Test func buildsToolRequest() throws {
        let urlRequest = try client.urlRequest(for: toolRequest)
        #expect(urlRequest.url?.absoluteString == "http://localhost:11434/api/chat")
        let body = try #require(JSONSerialization.jsonObject(with: urlRequest.httpBody ?? Data()) as? [String: Any])
        #expect(body["think"] as? Bool == false)
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "function")
        let function = try #require(tools[0]["function"] as? [String: Any])
        #expect(function["name"] as? String == "open")
        #expect(function["description"] as? String == "Open things")
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
        #expect(parameters["required"] as? [String] == ["kind", "target"])
        let properties = try #require(parameters["properties"] as? [String: [String: Any]])
        #expect(properties["kind"]?["type"] as? String == "string")
        #expect(properties["kind"]?["enum"] as? [String] == ["app", "file"])
        #expect(properties["target"]?["enum"] == nil)
        #expect(properties["target"]?["description"] as? String == "Name")
    }

    @Test func chatRequestHasNoTools() throws {
        let body = try #require(JSONSerialization.jsonObject(with: client.urlRequest(for: request).httpBody ?? Data()) as? [String: Any])
        #expect(body["tools"] == nil)
    }

    @Test func decodesToolCall() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"open","arguments":{"kind":"app","target":"Slack"}}}]},"done":true}"#.utf8)
        #expect(try await client.callTool(toolRequest) == .call(ToolCall(name: "open", arguments: ["kind": "app", "target": "Slack"])))
    }

    @Test func decodesTextReply() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"message":{"role":"assistant","content":"unsupported"},"done":true}"#.utf8)
        #expect(try await client.callTool(toolRequest) == .text("unsupported"))
    }

    @Test func toolCallThrowsOnErrorStatus() async {
        StubURLProtocol.status = 500
        StubURLProtocol.body = Data()
        await #expect(throws: ChatError.badStatus(500)) { try await client.callTool(toolRequest) }
    }
```

- [ ] **Step 2: Run `OllamaClientTests`.** Expected: build failure.

- [ ] **Step 3: Create `Services/Agent/ToolCalling.swift`.**

```swift
import Foundation

struct ToolParameter: Equatable {
    let name: String
    let description: String
    let allowed: [String]?
}

struct ToolDefinition: Equatable {
    let name: String
    let description: String
    let parameters: [ToolParameter]
}

struct ToolRequest: Equatable {
    let model: String
    let system: String
    let user: String
    let tools: [ToolDefinition]
    let timeout: Duration
}

struct ToolCall: Equatable {
    let name: String
    let arguments: [String: String]
}

enum ToolReply: Equatable {
    case call(ToolCall)
    case text(String)
}

protocol ToolCalling {
    func callTool(_ request: ToolRequest) async throws -> ToolReply
}
```

- [ ] **Step 4: Update `OllamaClient.swift`.**
  - Replace `complete(_:)` with a shared `send` helper, and add `callTool` and `urlRequest(for: ToolRequest)`:

```swift
    func complete(_ request: ChatRequest) async throws -> String {
        guard let content = try await send(urlRequest(for: request)).message.content else { throw ChatError.malformedResponse }
        return content
    }

    func callTool(_ request: ToolRequest) async throws -> ToolReply {
        let message = try await send(urlRequest(for: request)).message
        if let call = message.toolCalls?.first {
            return .call(ToolCall(name: call.function.name, arguments: call.function.arguments))
        }
        return .text(message.content ?? "")
    }

    func urlRequest(for request: ToolRequest) throws -> URLRequest {
        try post("api/chat", body: ChatBody(request), timeout: request.timeout)
    }

    private func send(_ urlRequest: URLRequest) async throws -> ChatReply {
        let (data, response) = try await session.data(for: urlRequest)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ChatError.malformedResponse }
        guard (200..<300).contains(status) else { throw ChatError.badStatus(status) }
        guard let reply = try? JSONDecoder().decode(ChatReply.self, from: data) else { throw ChatError.malformedResponse }
        return reply
    }
```

  - Change the declaration to `struct OllamaClient: ChatCompleting, ToolCalling`.
  - In `ChatBody`:
    - Add `let tools: [ToolBody]?`.
    - Add `tools` to `CodingKeys` (`case model, messages, stream, think, options, tools`).
    - Set `tools = nil` in `init(_ request: ChatRequest)`.
    - Add this second init:

```swift
    init(_ request: ToolRequest) {
        model = request.model
        messages = [
            Message(role: "system", content: request.system),
            Message(role: "user", content: request.user),
        ]
        tools = request.tools.map(ToolBody.init)
    }
```

  - Add these types below `ChatBody`:

```swift
private nonisolated struct ToolBody: Encodable {
    struct Function: Encodable {
        let name: String
        let description: String
        let parameters: Parameters
    }

    struct Parameters: Encodable {
        let type = "object"
        let required: [String]
        let properties: [String: Property]
    }

    struct Property: Encodable {
        let type = "string"
        let description: String
        let `enum`: [String]?
    }

    let type = "function"
    let function: Function

    init(_ definition: ToolDefinition) {
        function = Function(
            name: definition.name,
            description: definition.description,
            parameters: Parameters(
                required: definition.parameters.map(\.name),
                properties: Dictionary(uniqueKeysWithValues: definition.parameters.map {
                    ($0.name, Property(description: $0.description, enum: $0.allowed))
                })
            )
        )
    }
}
```

  - Replace `ChatReply`:

```swift
private nonisolated struct ChatReply: Decodable {
    struct Message: Decodable {
        let content: String?
        let toolCalls: [ToolCallBody]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCallBody: Decodable {
        struct Function: Decodable {
            let name: String
            let arguments: [String: String]
        }

        let function: Function
    }

    let message: Message
}
```

  Note: `Parameters.type` and `Property.type` are `let` constants with initial values. Synthesized `Encodable` still encodes them, as it already does for `ChatBody.stream`.

- [ ] **Step 5: Run the full suite.** Expected: all pass, including the existing `throwsOnMalformedBody` (`{"done":true}` has no `message`).

- [ ] **Step 6: Commit.** `git add -A && git commit -m "Call tools through Ollama's chat API"`

---

### Task 3: Tools, registry and agent runner

**Files:**
- Create: `Features/Agent/Tool.swift`, `Features/Agent/ToolRegistry.swift`, `Features/Agent/AgentError.swift`, `Features/Agent/AgentRunner.swift`
- Modify: `App/Logger+Veyra.swift`, `VeyraTests/Fakes.swift`
- Test: `VeyraTests/AgentRunnerTests.swift`

**Interfaces:**
- Consumes: `ToolCalling`, `ToolRequest`, `ToolReply`, `ToolCall`, `ToolDefinition` (Task 2). `CleanupModel`.
- Produces:
  - `enum ToolRisk { case immediate }`
  - `struct PreparedAction { let done: String; let failure: String; let perform: () async throws -> Void }`
  - `protocol Tool { var definition: ToolDefinition { get }; var risk: ToolRisk { get }; func prepare(_ arguments: [String: String]) async throws -> PreparedAction }`
  - `struct ToolRegistry { init(_ tools: [any Tool]); var definitions: [ToolDefinition]; func tool(named: String) -> (any Tool)? }`
  - `enum AgentError: Error, Equatable { case unsupported, invalidArguments, unavailable, noApp(String), noFile(String), badAddress; var message: String }`
  - `enum AgentOutcome: Equatable { case done(String), failed(String) }`
  - `protocol AgentRunning { func run(_ transcript: String) async -> AgentOutcome }`
  - `struct AgentRunner: AgentRunning { init(caller: ToolCalling, registry: ToolRegistry, models: [CleanupModel] = CleanupModel.chain); static let systemPrompt: String; func request(for transcript: String, model: CleanupModel) -> ToolRequest }`
  - `Logger.agent`

- [ ] **Step 1: Add fakes to `VeyraTests/Fakes.swift`.**

```swift
@MainActor
final class FakeToolCaller: ToolCalling {
    var replies: [String: Result<ToolReply, Error>] = [:]
    private(set) var requests: [ToolRequest] = []

    func callTool(_ request: ToolRequest) async throws -> ToolReply {
        requests.append(request)
        guard let reply = replies[request.model] else { throw TestError() }
        return try reply.get()
    }
}

@MainActor
final class FakeTool: Tool {
    let definition = ToolDefinition(name: "open", description: "Open", parameters: [])
    let risk = ToolRisk.immediate
    var prepareError: Error?
    var performError: Error?
    private(set) var preparedArguments: [[String: String]] = []
    private(set) var performCount = 0

    func prepare(_ arguments: [String: String]) async throws -> PreparedAction {
        preparedArguments.append(arguments)
        if let prepareError { throw prepareError }
        return PreparedAction(done: "Opened Slack", failure: "Couldn't open Slack") { [self] in
            performCount += 1
            if let performError { throw performError }
        }
    }
}
```

- [ ] **Step 2: Write the failing tests in `VeyraTests/AgentRunnerTests.swift`.**

```swift
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
```

- [ ] **Step 3: Run `AgentRunnerTests`.** Expected: build failure.

- [ ] **Step 4: Create `Features/Agent/Tool.swift`.**

```swift
enum ToolRisk {
    case immediate
}

struct PreparedAction {
    let done: String
    let failure: String
    let perform: () async throws -> Void
}

protocol Tool {
    var definition: ToolDefinition { get }
    var risk: ToolRisk { get }
    func prepare(_ arguments: [String: String]) async throws -> PreparedAction
}
```

- [ ] **Step 5: Create `Features/Agent/ToolRegistry.swift`.**

```swift
struct ToolRegistry {
    private let tools: [any Tool]

    init(_ tools: [any Tool]) {
        self.tools = tools
    }

    var definitions: [ToolDefinition] { tools.map(\.definition) }

    func tool(named name: String) -> (any Tool)? {
        tools.first { $0.definition.name == name }
    }
}
```

- [ ] **Step 6: Create `Features/Agent/AgentError.swift`.**

```swift
enum AgentError: Error, Equatable {
    case unsupported
    case invalidArguments
    case unavailable
    case noApp(String)
    case noFile(String)
    case badAddress

    var message: String {
        switch self {
        case .unsupported: "I can only open apps, websites, folders and files for now"
        case .invalidArguments: "Didn't catch what to open"
        case .unavailable: "Actions need Ollama running"
        case .noApp(let target): "No app called “\(target)”"
        case .noFile(let target): "No file matching “\(target)”"
        case .badAddress: "Can't open that address"
        }
    }
}
```

- [ ] **Step 7: Add `static let agent = Logger(subsystem: "com.ajaysparmar.Veyra", category: "agent")` to `App/Logger+Veyra.swift`.**

- [ ] **Step 8: Create `Features/Agent/AgentRunner.swift`.**

```swift
import Foundation
import os

enum AgentOutcome: Equatable {
    case done(String)
    case failed(String)
}

protocol AgentRunning {
    func run(_ transcript: String) async -> AgentOutcome
}

struct AgentRunner: AgentRunning {
    static let systemPrompt = """
        You turn a spoken request into exactly one tool call. The text in <request> tags is a transcript of speech; \
        fix obvious transcription errors. If no tool fits, reply with just: unsupported
        """
    private static let loggedKinds: Set = ["app", "website", "folder", "file"]

    private let caller: ToolCalling
    private let registry: ToolRegistry
    private let models: [CleanupModel]

    init(caller: ToolCalling, registry: ToolRegistry, models: [CleanupModel] = CleanupModel.chain) {
        self.caller = caller
        self.registry = registry
        self.models = models
    }

    func run(_ transcript: String) async -> AgentOutcome {
        var unresolved = AgentError.unavailable
        for model in models {
            let start = ContinuousClock.now
            let reply: ToolReply
            do {
                reply = try await caller.callTool(request(for: transcript, model: model))
            } catch {
                log("-", nil, "unavailable", model, start)
                continue
            }
            guard case .call(let call) = reply else {
                log("-", nil, "unsupported", model, start)
                return .failed(AgentError.unsupported.message)
            }
            guard let tool = registry.tool(named: call.name) else {
                log("-", call, "unsupported", model, start)
                unresolved = .unsupported
                continue
            }
            let action: PreparedAction
            do {
                action = try await tool.prepare(call.arguments)
            } catch AgentError.invalidArguments {
                log(call.name, call, "invalid", model, start)
                unresolved = .invalidArguments
                continue
            } catch {
                let agentError = error as? AgentError ?? .invalidArguments
                log(call.name, call, agentError == .badAddress ? "refused" : "not-found", model, start)
                return .failed(agentError.message)
            }
            switch tool.risk {
            case .immediate: break
            }
            do {
                try await action.perform()
                log(call.name, call, "opened", model, start)
                return .done(action.done)
            } catch {
                log(call.name, call, "failed", model, start)
                return .failed(action.failure)
            }
        }
        return .failed(unresolved.message)
    }

    func request(for transcript: String, model: CleanupModel) -> ToolRequest {
        ToolRequest(
            model: model.name,
            system: Self.systemPrompt,
            user: "<request>\(transcript)</request>",
            tools: registry.definitions,
            timeout: model.timeout(forWordCount: CleanupGuard.words(in: transcript).count)
        )
    }

    private func log(_ name: String, _ call: ToolCall?, _ outcome: String, _ model: CleanupModel, _ start: ContinuousClock.Instant) {
        let kind = call?.arguments["kind"].flatMap { Self.loggedKinds.contains($0) ? $0 : nil } ?? "-"
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
        Logger.agent.info("Tool \(name, privacy: .public) kind \(kind, privacy: .public) \(outcome, privacy: .public) via \(model.name, privacy: .public) in \(milliseconds) ms")
    }
}
```

- [ ] **Step 9: Run `AgentRunnerTests`.** Expected: all pass.

- [ ] **Step 10: Commit.** `git add -A && git commit -m "Add the tool abstraction and an agent runner with local-first fallback"`

---

### Task 4: Pure resolvers

**Files:**
- Create: `Features/Agent/Open/AppResolver.swift`, `Features/Agent/Open/WebsiteResolver.swift`, `Features/Agent/Open/FolderResolver.swift`, `Features/Agent/Open/FileSearcher.swift`
- Test: `VeyraTests/OpenResolverTests.swift`

**Interfaces:**
- Produces:
  - `AppResolver.match(_ query: String, in names: [String]) -> String?`
  - `WebsiteResolver.url(for target: String) -> URL?`
  - `enum StandardFolder: String, CaseIterable { case desktop, documents, downloads, home, pictures, music, movies; var name: String; func url(in home: URL) -> URL }`
  - `FolderResolver.folder(for target: String) -> StandardFolder?`
  - `struct FileResult: Equatable { let url: URL; let name: String; let lastUsed: Date? }`
  - `FileSearcher.words(in target: String) -> [String]`
  - `FileSearcher.rank(_ results: [FileResult], for words: [String]) -> [FileResult]`

- [ ] **Step 1: Write the failing tests in `VeyraTests/OpenResolverTests.swift`.**

```swift
import Foundation
import Testing
@testable import Veyra

@MainActor
struct OpenResolverTests {
    private let apps = ["Slack", "Visual Studio Code", "Google Chrome", "Safari", "Xcode", "Notes", "Spotify", "System Settings", "Messages", "Mail"]

    @Test(arguments: [
        ("Slack", "Slack"),
        ("slack", "Slack"),
        ("VS code", "Visual Studio Code"),
        ("V S code", "Visual Studio Code"),
        ("visual studio code", "Visual Studio Code"),
        ("chrome", "Google Chrome"),
        ("Slak", "Slack"),
        ("Spotfy", "Spotify"),
        ("system settings", "System Settings"),
    ])
    func matchesApp(query: String, expected: String) {
        #expect(AppResolver.match(query, in: apps) == expected)
    }

    @Test(arguments: ["Photoshop", "", "ma", "zz"])
    func noAppMatch(query: String) {
        #expect(AppResolver.match(query, in: apps) == nil)
    }

    @Test func tieGoesToShortestName() {
        #expect(AppResolver.match("mail", in: ["Mailspring", "Mail"]) == "Mail")
        #expect(AppResolver.match("code", in: ["Xcode", "Visual Studio Code"]) == "Xcode")
    }

    @Test(arguments: [
        ("github.com", "https://github.com"),
        ("github dot com", "https://github.com"),
        ("YouTube.com.", "https://youtube.com"),
        ("https://x.com/a", "https://x.com/a"),
        ("http://example.org", "http://example.org"),
        (" mail.google.com ", "https://mail.google.com"),
    ])
    func websiteURL(target: String, expected: String) {
        #expect(WebsiteResolver.url(for: target)?.absoluteString == expected)
    }

    @Test(arguments: ["file:///etc/hosts", "javascript:alert(1)", "not a site", "", "ftp://example.com", ".com"])
    func refusesWebsite(target: String) {
        #expect(WebsiteResolver.url(for: target) == nil)
    }

    @Test(arguments: [
        ("Downloads", StandardFolder.downloads),
        ("my downloads folder", .downloads),
        ("the Desktop", .desktop),
        ("Documents", .documents),
        ("home folder", .home),
        ("my Pictures", .pictures),
        ("Music", .music),
        ("movies", .movies),
    ])
    func standardFolder(target: String, expected: StandardFolder) {
        #expect(FolderResolver.folder(for: target) == expected)
    }

    @Test(arguments: ["Veyra project", "Downloads backup", ""])
    func nonStandardFolder(target: String) {
        #expect(FolderResolver.folder(for: target) == nil)
    }

    @Test func folderURLs() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        #expect(StandardFolder.home.url(in: home) == home)
        #expect(StandardFolder.downloads.url(in: home).path() == "/Users/me/Downloads/")
        #expect(StandardFolder.home.name == "Home")
        #expect(StandardFolder.downloads.name == "Downloads")
    }

    @Test func searchWordsDropStopWords() {
        #expect(FileSearcher.words(in: "the PDF about tax returns") == ["pdf", "about", "tax", "returns"])
        #expect(FileSearcher.words(in: "my resume") == ["resume"])
        #expect(FileSearcher.words(in: "the file called notes") == ["notes"])
    }

    private func file(_ name: String, daysAgo: Double?) -> FileResult {
        FileResult(
            url: URL(filePath: "/Users/me/\(name)"),
            name: name,
            lastUsed: daysAgo.map { Date(timeIntervalSince1970: 1_000_000 - $0 * 86_400) }
        )
    }

    @Test func ranksByMatchedWordsThenRecency() {
        let old = file("Tax Return 2024.pdf", daysAgo: 300)
        let recent = file("Tax Notes.txt", daysAgo: 1)
        let both = file("Tax Returns Final.pdf", daysAgo: 30)
        #expect(FileSearcher.rank([recent, old, both], for: ["tax", "returns"]) == [both, recent, old])
    }

    @Test func missingDatesRankLastThenShorterName() {
        let undated = file("Resume.pdf", daysAgo: nil)
        let dated = file("Resume Final.pdf", daysAgo: 5)
        let undatedLong = file("Resume Old Copy.pdf", daysAgo: nil)
        #expect(FileSearcher.rank([undatedLong, undated, dated], for: ["resume"]) == [dated, undated, undatedLong])
    }

    @Test func requiresHalfTheWords() {
        let one = file("Invoice.pdf", daysAgo: 1)
        #expect(FileSearcher.rank([one], for: ["invoice", "september", "acme"]).isEmpty)
        #expect(FileSearcher.rank([one], for: ["invoice", "september"]) == [one])
    }

    @Test func matchingIgnoresCaseAndAccents() {
        let résumé = file("Résumé.pdf", daysAgo: 1)
        #expect(FileSearcher.rank([résumé], for: ["resume"]) == [résumé])
    }
}
```

- [ ] **Step 2: Run `OpenResolverTests`.** Expected: build failure.

- [ ] **Step 3: Create `Features/Agent/Open/AppResolver.swift`.**

```swift
import Foundation

enum AppResolver {
    static func match(_ query: String, in names: [String]) -> String? {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return nil }
        let queryWords = mergedLetters(words(query))
        let tiers: [(String) -> Bool] = [
            { normalized($0) == normalizedQuery },
            { consumes(queryWords[...], words($0)[...]) },
            { normalizedQuery.count >= 3 && normalized($0).contains(normalizedQuery) },
            { isNearMiss(normalizedQuery, normalized($0)) },
        ]
        for tier in tiers {
            if let best = names.filter(tier).min(by: { ($0.count, $0) < ($1.count, $1) }) { return best }
        }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func mergedLetters(_ words: [String]) -> [String] {
        var merged: [String] = []
        var run = ""
        for word in words {
            if word.count == 1 {
                run += word
            } else {
                if !run.isEmpty { merged.append(run); run = "" }
                merged.append(word)
            }
        }
        if !run.isEmpty { merged.append(run) }
        return merged
    }

    private static func consumes(_ query: ArraySlice<String>, _ name: ArraySlice<String>) -> Bool {
        guard let word = query.first else { return name.isEmpty }
        if name.first == word, consumes(query.dropFirst(), name.dropFirst()) { return true }
        guard word.count >= 2, name.count >= word.count else { return false }
        let initials = String(name.prefix(word.count).compactMap(\.first))
        return initials == word && consumes(query.dropFirst(), name.dropFirst(word.count))
    }

    private static func isNearMiss(_ query: String, _ name: String) -> Bool {
        let limit = query.count >= 5 ? 2 : query.count == 4 ? 1 : 0
        return limit > 0 && distance(query, name) <= limit
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
```

  `mergedLetters` joins runs of single letters, so "v s code" becomes ["vs", "code"]. The contains tier needs a query of at least 3 characters, so "ma" doesn't match Mail. This is a ruling beyond the spec's wording.

- [ ] **Step 4: Create `Features/Agent/Open/WebsiteResolver.swift`.**

```swift
import Foundation

enum WebsiteResolver {
    static func url(for target: String) -> URL? {
        var text = target.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(" dot ", with: ".")
            .replacing(#/\s+/#, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme),
              let host = url.host(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            return nil
        }
        return url
    }
}
```

- [ ] **Step 5: Create `Features/Agent/Open/FolderResolver.swift`.**

```swift
import Foundation

enum StandardFolder: String, CaseIterable {
    case desktop, documents, downloads, home, pictures, music, movies

    var name: String { rawValue.capitalized }

    func url(in home: URL) -> URL {
        self == .home ? home : home.appending(path: name, directoryHint: .isDirectory)
    }
}

enum FolderResolver {
    private static let ignored: Set = ["my", "the", "folder"]

    static func folder(for target: String) -> StandardFolder? {
        let words = target.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { !ignored.contains($0) }
        return StandardFolder(rawValue: words.joined(separator: " "))
    }
}
```

- [ ] **Step 6: Create `Features/Agent/Open/FileSearcher.swift`.**

```swift
import Foundation

struct FileResult: Equatable {
    let url: URL
    let name: String
    let lastUsed: Date?
}

enum FileSearcher {
    private static let stopWords: Set = ["the", "my", "a", "an", "file", "folder", "document", "called", "named"]

    static func words(in target: String) -> [String] {
        target.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stopWords.contains($0) }
    }

    static func rank(_ results: [FileResult], for words: [String]) -> [FileResult] {
        let minimum = max(1, (words.count + 1) / 2)
        return results
            .map { ($0, matchCount(of: words, in: $0.name)) }
            .filter { $0.1 >= minimum }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                switch (a.0.lastUsed, b.0.lastUsed) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.0.name.count < b.0.name.count
                }
            }
            .map(\.0)
    }

    private static func matchCount(of words: [String], in name: String) -> Int {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return words.count { folded.contains($0) }
    }
}
```

- [ ] **Step 7: Run `OpenResolverTests`.** Expected: all pass.

- [ ] **Step 8: Commit.** `git add -A && git commit -m "Resolve apps, websites, folders and files from spoken targets"`

---

### Task 5: The `open` tool and its system adapters

**Files:**
- Create: `Features/Agent/Open/OpenTool.swift`, `Services/System/WorkspaceOpening.swift`, `Services/System/SpotlightFileSearcher.swift`
- Modify: `VeyraTests/Fakes.swift`
- Test: `VeyraTests/OpenToolTests.swift`

**Interfaces:**
- Consumes: the Task 4 resolvers. `Tool`, `PreparedAction`, `AgentError` (Task 3).
- Produces:
  - `struct InstalledApp: Equatable { let name: String; let url: URL }`
  - `protocol AppListing { func installedApps() -> [InstalledApp] }`
  - `protocol WorkspaceOpening { func open(_ url: URL) async throws; func openApplication(at url: URL) async throws }`
  - `protocol FileSearching { func search(_ words: [String], foldersOnly: Bool) async -> [FileResult] }`
  - `struct OpenTool: Tool { init(apps: AppListing, files: FileSearching, workspace: WorkspaceOpening, home: URL) }`
  - `InstalledAppDirectory`, `NSWorkspaceOpener`, `SpotlightFileSearcher`

- [ ] **Step 1: Add fakes to `VeyraTests/Fakes.swift`.**

```swift
struct FakeAppListing: AppListing {
    var apps: [InstalledApp] = []
    func installedApps() -> [InstalledApp] { apps }
}

@MainActor
final class FakeFileSearching: FileSearching {
    var results: [FileResult] = []
    private(set) var searches: [(words: [String], foldersOnly: Bool)] = []

    func search(_ words: [String], foldersOnly: Bool) async -> [FileResult] {
        searches.append((words, foldersOnly))
        return results
    }
}

@MainActor
final class FakeWorkspace: WorkspaceOpening {
    var error: Error?
    private(set) var opened: [URL] = []
    private(set) var launched: [URL] = []

    func open(_ url: URL) async throws {
        if let error { throw error }
        opened.append(url)
    }

    func openApplication(at url: URL) async throws {
        if let error { throw error }
        launched.append(url)
    }
}
```

- [ ] **Step 2: Write the failing tests in `VeyraTests/OpenToolTests.swift`.**

```swift
import Foundation
import Testing
@testable import Veyra

@MainActor
struct OpenToolTests {
    private let slack = InstalledApp(name: "Slack", url: URL(filePath: "/Applications/Slack.app"))
    private let files = FakeFileSearching()
    private let workspace = FakeWorkspace()
    private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

    private var tool: OpenTool {
        OpenTool(apps: FakeAppListing(apps: [slack]), files: files, workspace: workspace, home: home)
    }

    private func result(_ name: String, daysAgo: Double) -> FileResult {
        FileResult(url: URL(filePath: "/Users/me/\(name)"), name: name, lastUsed: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86_400))
    }

    @Test func definitionMatchesTheSpec() {
        #expect(tool.definition.name == "open")
        #expect(tool.definition.parameters.map(\.name) == ["kind", "target"])
        #expect(tool.definition.parameters[0].allowed == ["app", "website", "folder", "file"])
        #expect(tool.risk == .immediate)
    }

    @Test func opensAppOnlyOnPerform() async throws {
        let action = try await tool.prepare(["kind": "app", "target": "slak"])
        #expect(workspace.launched.isEmpty)
        #expect(action.done == "Opened Slack")
        #expect(action.failure == "Couldn't open Slack")
        try await action.perform()
        #expect(workspace.launched == [slack.url])
    }

    @Test func unknownAppIsNotFound() async {
        await #expect(throws: AgentError.noApp("Photoshop")) { try await tool.prepare(["kind": "app", "target": "Photoshop"]) }
    }

    @Test func opensWebsite() async throws {
        let action = try await tool.prepare(["kind": "website", "target": "github dot com"])
        #expect(action.done == "Opened github.com")
        try await action.perform()
        #expect(workspace.opened == [URL(string: "https://github.com")!])
    }

    @Test func refusesBadAddress() async {
        await #expect(throws: AgentError.badAddress) { try await tool.prepare(["kind": "website", "target": "file:///etc/hosts"]) }
    }

    @Test func opensStandardFolderWithoutSearching() async throws {
        let action = try await tool.prepare(["kind": "folder", "target": "my downloads"])
        #expect(action.done == "Opened Downloads")
        try await action.perform()
        #expect(workspace.opened == [StandardFolder.downloads.url(in: home)])
        #expect(files.searches.isEmpty)
    }

    @Test func nonStandardFolderSearchesFoldersOnly() async throws {
        files.results = [result("Veyra", daysAgo: 1)]
        let action = try await tool.prepare(["kind": "folder", "target": "Veyra project"])
        #expect(files.searches.map(\.foldersOnly) == [true])
        #expect(files.searches.map(\.words) == [["veyra", "project"]])
        #expect(action.done == "Opened Veyra")
    }

    @Test func opensBestFileAndCountsOthers() async throws {
        files.results = [result("Resume Old.pdf", daysAgo: 200), result("Resume.pdf", daysAgo: 2), result("Resume Draft.pdf", daysAgo: 90)]
        let action = try await tool.prepare(["kind": "file", "target": "my resume"])
        #expect(files.searches.map(\.foldersOnly) == [false])
        #expect(action.done == "Opened Resume.pdf · 2 other matches")
        try await action.perform()
        #expect(workspace.opened == [URL(filePath: "/Users/me/Resume.pdf")])
    }

    @Test func oneOtherMatchIsSingular() async throws {
        files.results = [result("Resume.pdf", daysAgo: 2), result("Resume Draft.pdf", daysAgo: 90)]
        let action = try await tool.prepare(["kind": "file", "target": "resume"])
        #expect(action.done == "Opened Resume.pdf · 1 other match")
    }

    @Test func noFileIsNotFound() async {
        await #expect(throws: AgentError.noFile("resume")) { try await tool.prepare(["kind": "file", "target": "resume"]) }
    }

    @Test(arguments: [
        ["target": "Slack"],
        ["kind": "app"],
        ["kind": "app", "target": "  "],
        ["kind": "program", "target": "Slack"],
    ])
    func invalidArguments(arguments: [String: String]) async {
        await #expect(throws: AgentError.invalidArguments) { try await tool.prepare(arguments) }
    }

    @Test func performFailurePropagates() async throws {
        workspace.error = TestError()
        let action = try await tool.prepare(["kind": "app", "target": "Slack"])
        await #expect(throws: TestError.self) { try await action.perform() }
    }
}
```

- [ ] **Step 3: Run `OpenToolTests`.** Expected: build failure.

- [ ] **Step 4: Create `Services/System/WorkspaceOpening.swift`.**

```swift
import AppKit

struct InstalledApp: Equatable {
    let name: String
    let url: URL
}

protocol AppListing {
    func installedApps() -> [InstalledApp]
}

protocol WorkspaceOpening {
    func open(_ url: URL) async throws
    func openApplication(at url: URL) async throws
}

struct InstalledAppDirectory: AppListing {
    func installedApps() -> [InstalledApp] {
        let fileManager = FileManager.default
        let directories = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            + [fileManager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)]
        return directories.flatMap { directory in
            ((try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
                .map { InstalledApp(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
        }
    }
}

struct WorkspaceOpenError: Error {}

struct NSWorkspaceOpener: WorkspaceOpening {
    func open(_ url: URL) async throws {
        guard NSWorkspace.shared.open(url) else { throw WorkspaceOpenError() }
    }

    func openApplication(at url: URL) async throws {
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
```

- [ ] **Step 5: Create `Services/System/SpotlightFileSearcher.swift`.**

```swift
import Foundation

protocol FileSearching {
    func search(_ words: [String], foldersOnly: Bool) async -> [FileResult]
}

final class SpotlightFileSearcher: FileSearching {
    private static let timeout: Duration = .seconds(2)
    private static let resultLimit = 500

    func search(_ words: [String], foldersOnly: Bool) async -> [FileResult] {
        guard !words.isEmpty else { return [] }
        let query = NSMetadataQuery()
        let names = words.map { NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, $0) }
        var predicates: [NSPredicate] = [NSCompoundPredicate(orPredicateWithSubpredicates: names)]
        if foldersOnly {
            predicates.append(NSPredicate(format: "%K == %@", NSMetadataItemContentTypeKey, "public.folder"))
        }
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library", directoryHint: .isDirectory).path()

        return await withCheckedContinuation { continuation in
            var isFinished = false
            var observer: NSObjectProtocol?
            let finish = {
                guard !isFinished else { return }
                isFinished = true
                query.stop()
                observer.map(NotificationCenter.default.removeObserver)
                let items = (query.results as? [NSMetadataItem] ?? []).prefix(Self.resultLimit)
                let results = items.compactMap { item -> FileResult? in
                    guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                          !path.hasPrefix(library), !path.contains("/.") else { return nil }
                    let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String ?? URL(filePath: path).lastPathComponent
                    return FileResult(url: URL(filePath: path), name: name, lastUsed: item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date)
                }
                continuation.resume(returning: results)
            }
            observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { _ in
                MainActor.assumeIsolated { finish() }
            }
            guard query.start() else { return finish() }
            Task {
                try? await Task.sleep(for: Self.timeout)
                finish()
            }
        }
    }
}
```

- [ ] **Step 6: Create `Features/Agent/Open/OpenTool.swift`.**

```swift
import Foundation

struct OpenTool: Tool {
    private enum Kind: String, CaseIterable {
        case app, website, folder, file
    }

    let definition = ToolDefinition(
        name: "open",
        description: "Open an installed app, a website, a standard user folder, or a file/folder found by name.",
        parameters: [
            ToolParameter(
                name: "kind",
                description: "app = installed application; website = a domain or well-known site; folder = Desktop/Documents/Downloads/Home/Pictures/Music/Movies; file = any other file or folder searched by name",
                allowed: Kind.allCases.map(\.rawValue)
            ),
            ToolParameter(
                name: "target",
                description: "App name, domain (e.g. github.com), folder name, or file search words, cleaned of filler",
                allowed: nil
            ),
        ]
    )
    let risk = ToolRisk.immediate

    private let apps: AppListing
    private let files: FileSearching
    private let workspace: WorkspaceOpening
    private let home: URL

    init(apps: AppListing, files: FileSearching, workspace: WorkspaceOpening, home: URL) {
        self.apps = apps
        self.files = files
        self.workspace = workspace
        self.home = home
    }

    func prepare(_ arguments: [String: String]) async throws -> PreparedAction {
        guard let kind = arguments["kind"].flatMap(Kind.init(rawValue:)),
              let target = arguments["target"]?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
            throw AgentError.invalidArguments
        }
        switch kind {
        case .app:
            let installed = apps.installedApps()
            guard let name = AppResolver.match(target, in: installed.map(\.name)),
                  let app = installed.first(where: { $0.name == name }) else {
                throw AgentError.noApp(target)
            }
            return action(app.name) { [workspace] in try await workspace.openApplication(at: app.url) }
        case .website:
            guard let url = WebsiteResolver.url(for: target), let host = url.host() else { throw AgentError.badAddress }
            return action(host) { [workspace] in try await workspace.open(url) }
        case .folder:
            if let folder = FolderResolver.folder(for: target) {
                let url = folder.url(in: home)
                return action(folder.name) { [workspace] in try await workspace.open(url) }
            }
            return try await search(target, foldersOnly: true)
        case .file:
            return try await search(target, foldersOnly: false)
        }
    }

    private func search(_ target: String, foldersOnly: Bool) async throws -> PreparedAction {
        let words = FileSearcher.words(in: target)
        let ranked = words.isEmpty ? [] : FileSearcher.rank(await files.search(words, foldersOnly: foldersOnly), for: words)
        guard let best = ranked.first else { throw AgentError.noFile(target) }
        let others = ranked.count - 1
        let suffix = others == 0 ? "" : " · \(others) other match\(others == 1 ? "" : "es")"
        return action(best.name, suffix: suffix) { [workspace] in try await workspace.open(best.url) }
    }

    private func action(_ name: String, suffix: String = "", perform: @escaping () async throws -> Void) -> PreparedAction {
        PreparedAction(done: "Opened \(name)\(suffix)", failure: "Couldn't open \(name)", perform: perform)
    }
}
```

- [ ] **Step 7: Run `OpenToolTests`, then the full suite.** Expected: all pass.

- [ ] **Step 8: Commit.** `git add -A && git commit -m "Add the open tool with app, website, folder and Spotlight adapters"`

---

### Task 6: Route actions in the coordinator and show them

**Files:**
- Modify: `Features/Dictation/DictationCoordinator.swift`, `Features/Dictation/DictationState.swift`, `Features/Dictation/DictationState+Presentation.swift`, `Features/Dictation/RecordingOverlay.swift`, `App/AppDependencies.swift`, `VeyraTests/Fakes.swift`
- Test: `VeyraTests/DictationCoordinatorTests.swift`, `VeyraTests/DictationStatePresentationTests.swift`

**Interfaces:**
- Consumes: `AgentRunning`, `AgentOutcome` (Task 3). `Gesture` and `coordinator.gesture` (Task 1). `OpenTool` and the adapters (Task 5).
- Produces: `DictationState.acting`, `DictationState.acted(message: String)`, and `DictationCoordinator.init(…, agent: AgentRunning, …)`, with `agent:` placed after `contextProvider:`.

- [ ] **Step 1: Add a fake to `VeyraTests/Fakes.swift`.**

```swift
@MainActor
final class FakeAgent: AgentRunning {
    var outcome = AgentOutcome.done("Opened Slack")
    private(set) var transcripts: [String] = []

    func run(_ transcript: String) async -> AgentOutcome {
        transcripts.append(transcript)
        return outcome
    }
}
```

- [ ] **Step 2: Write the failing tests.**
  - In `DictationCoordinatorTests`, add `private let agent = FakeAgent()` and pass `agent: agent,` after `contextProvider: context,` in `readyCoordinator`. Then append:

```swift
    private func act(_ transcript: String, on coordinator: DictationCoordinator) async {
        transcriber.transcript = transcript
        hotkey.send(.pressed(.act), .released)
        await coordinator.transcription?.value
    }

    @Test func actionGoesToTheAgentOnly() async {
        let processor = RecordingProcessor()
        let coordinator = await readyCoordinator(processor: processor)
        await act("Open Slack.", on: coordinator)
        #expect(agent.transcripts == ["Open Slack."])
        #expect(processor.modes.isEmpty)
        #expect(inserter.inserted.isEmpty)
        #expect(keystrokes.sentChords.isEmpty)
        #expect(coordinator.state == .acted(message: "Opened Slack"))
    }

    @Test func commandPhraseInActionModeStillGoesToTheAgent() async {
        let coordinator = await readyCoordinator()
        await act("undo that", on: coordinator)
        #expect(agent.transcripts == ["undo that"])
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func actionFailureIsShown() async {
        agent.outcome = .failed("No app called “Foo”")
        let coordinator = await readyCoordinator()
        await act("open foo", on: coordinator)
        #expect(coordinator.state == .failed(message: "No app called “Foo”"))
    }

    @Test func actionResultReturnsToIdle() async {
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await act("Open Slack.", on: coordinator)
        await coordinator.recovery?.value
        #expect(coordinator.state == .idle)
    }

    @Test func emptyActionTranscriptDoesNothing() async {
        let coordinator = await readyCoordinator()
        await act("", on: coordinator)
        #expect(agent.transcripts.isEmpty)
        #expect(coordinator.state == .idle)
    }

    @Test func actionGestureIsVisibleWhileRecording() async {
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        hotkey.send(.pressed(.act))
        #expect(coordinator.gesture == .act)
        hotkey.send(.released)
        await coordinator.transcription?.value
        await coordinator.recovery?.value
        hotkey.send(.pressed(.dictate))
        #expect(coordinator.gesture == .dictate)
    }

    @Test func actionClearsScratchThat() async {
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await dictate(coordinator)
        await act("Open Slack.", on: coordinator)
        await coordinator.recovery?.value
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func dictationIsUnchangedAfterAnAction() async {
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await act("Open Slack.", on: coordinator)
        await coordinator.recovery?.value
        await dictate(coordinator)
        #expect(inserter.inserted == ["hello world"])
        #expect(agent.transcripts == ["Open Slack."])
    }
```

  - In `DictationStatePresentationTests`, add `(.acting, "Working…")` and `(.acted(message: "Opened Slack"), "Opened Slack")` to `statusText`, and `(.acting, true)` and `(.acted(message: "x"), true)` to `overlayVisibility`.

- [ ] **Step 3: Run the full suite.** Expected: build failure, because of the `agent:` argument and the `.acting` and `.acted` cases.

- [ ] **Step 4: In `DictationState.swift`, add `case acting` and `case acted(message: String)` after `transcribing`.**

- [ ] **Step 5: Update `DictationState+Presentation.swift`.**
  - `menuBarSymbol`: add `case .acting: "bolt"` and `case .acted: "checkmark"`.
  - `statusText`: add `case .acting: "Working…"` and `case .acted(let message): message`.
  - `showsOverlay`: add `.acting, .acted` to the `true` list.

- [ ] **Step 6: Update `DictationCoordinator.swift`.**
  - Add `private let agent: AgentRunning`, an `agent: AgentRunning,` init parameter after `contextProvider:`, and `self.agent = agent`.
  - In `finishRecording()`, replace the `transcription = Task …` line with:

```swift
        transcription = Task { [context = self.context, gesture = self.gesture] in
            switch gesture {
            case .dictate: await transcribeAndRoute(samples, in: context)
            case .act: await transcribeAndAct(samples)
            }
        }
```

  - Add:

```swift
    private func transcribeAndAct(_ samples: [Float]) async {
        lastInsertion = nil
        do {
            let transcript = try await transcriber.transcribe(samples)
            guard !transcript.isEmpty else {
                state = .idle
                return
            }
            state = .acting
            switch await agent.run(transcript) {
            case .done(let message): showBriefly(.acted(message: message))
            case .failed(let message): showBriefly(.failed(message: message))
            }
        } catch {
            fail(error.localizedDescription)
        }
    }
```

  - Replace `fail(_:)` with:

```swift
    private func fail(_ message: String) {
        Logger.dictation.error("\(message, privacy: .public)")
        showBriefly(.failed(message: message))
    }

    private func showBriefly(_ shown: DictationState) {
        state = shown
        recovery = Task { [failureDisplayDuration] in
            try? await Task.sleep(for: failureDisplayDuration)
            if state == shown { state = .idle }
        }
    }
```

  `transcribeAndAct` shows agent failures with `showBriefly` rather than `fail`, because `fail` logs its message as public, and agent messages can contain app or file names. `AgentRunner` has already logged the outcome.

- [ ] **Step 7: Update `RecordingOverlay.swift`'s `content`.**

```swift
        case .recording(let level) where coordinator.gesture == .act:
            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
            Text("Listening for an action…").lineLimit(1)
            LevelMeter(level: level)
        case .recording(let level):
            Image(systemName: "mic.fill").foregroundStyle(.red)
            LevelMeter(level: level)
        case .transcribing:
            ProgressView().controlSize(.small)
            Text("Transcribing")
        case .acting:
            ProgressView().controlSize(.small)
            Text("Working…")
        case .acted(let message):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message).lineLimit(1)
```

  Keep the existing `.failed` and default cases. Widen `size` to `NSSize(width: 320, height: 56)` so "Listening for an action…" and a meter fit.

- [ ] **Step 8: Update `App/AppDependencies.swift`.** Before the coordinator:

```swift
        let client = OllamaClient()
        let openTool = OpenTool(
            apps: InstalledAppDirectory(),
            files: SpotlightFileSearcher(),
            workspace: NSWorkspaceOpener(),
            home: FileManager.default.homeDirectoryForCurrentUser
        )
```

  Use `processor: OllamaTextProcessor(client: client)`, and add `agent: AgentRunner(caller: client, registry: ToolRegistry([openTool])),` after `contextProvider:`.

- [ ] **Step 9: Run the full suite.** Expected: all pass.

- [ ] **Step 10: Commit.** `git add -A && git commit -m "Run actions from Fn + Control and show the result"`

---

### Task 7: Starter agent evaluation (opt-in)

**Files:**
- Test: `VeyraTests/AgentEvalTests.swift`

**Interfaces:**
- Consumes: `AgentRunner.request(for:model:)`, `ToolRegistry`, `OpenTool.definition`, `OllamaClient.callTool`, and the Task 4 resolvers.

- [ ] **Step 1: Create `VeyraTests/AgentEvalTests.swift`.**

```swift
import Foundation
import Testing
@testable import Veyra

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["VEYRA_EVAL"] != nil))
struct AgentEvalTests {
    enum Expect {
        case app(String)
        case website(Set<String>)
        case folder(StandardFolder)
        case file(String)
        case unsupported
    }

    private static let apps = ["Slack", "Visual Studio Code", "Google Chrome", "Safari", "Xcode", "Notes", "Spotify", "System Settings", "Ghostty", "Finder"]

    private static let cases: [(String, Expect)] = [
        ("Open Slack.", .app("Slack")),
        ("open visual studio code", .app("Visual Studio Code")),
        ("Open V S code.", .app("Visual Studio Code")),
        ("Um, can you open Spotify?", .app("Spotify")),
        ("open google chrome", .app("Google Chrome")),
        ("Open Safari please.", .app("Safari")),
        ("launch xcode", .app("Xcode")),
        ("open system settings", .app("System Settings")),
        ("Open notes.", .app("Notes")),
        ("open github dot com", .website(["github.com"])),
        ("Open YouTube.", .website(["youtube.com", "www.youtube.com"])),
        ("Open Gmail.", .website(["gmail.com", "mail.google.com"])),
        ("open wikipedia", .website(["wikipedia.org", "www.wikipedia.org", "en.wikipedia.org"])),
        ("go to apple dot com", .website(["apple.com", "www.apple.com"])),
        ("open my downloads folder", .folder(.downloads)),
        ("Open the desktop.", .folder(.desktop)),
        ("show me my documents", .folder(.documents)),
        ("open my home folder", .folder(.home)),
        ("open pictures", .folder(.pictures)),
        ("Open my resume.", .file("resume")),
        ("open the Veyra project folder", .file("veyra")),
        ("open the pdf about tax returns from last year", .file("tax")),
        ("open the invoice for september", .file("invoice")),
        ("What's the weather tomorrow?", .unsupported),
        ("send a message to John", .unsupported),
        ("tell me a joke", .unsupported),
    ]

    private let runner = AgentRunner(
        caller: OllamaClient(),
        registry: ToolRegistry([OpenTool(apps: FakeAppListing(), files: FakeFileSearching(), workspace: FakeWorkspace(), home: URL(filePath: "/"))])
    )

    @Test(arguments: ["gemma4:latest", "gemma4:cloud"])
    func accuracy(modelName: String) async throws {
        let model = CleanupModel(name: modelName, baseTimeout: .seconds(60), timeoutPerWord: .zero)
        var failures: [String] = []
        for (transcript, expect) in Self.cases {
            let reply = try? await OllamaClient().callTool(runner.request(for: transcript, model: model))
            if !Self.passes(reply, expect) { failures.append("\(transcript) → \(String(describing: reply))") }
        }
        let passed = Self.cases.count - failures.count
        print("[eval] \(model.name): \(passed)/\(Self.cases.count)\n" + failures.map { "  ✗ \($0)" }.joined(separator: "\n"))
        #expect(passed * 10 >= Self.cases.count * 9, "\(model.name) scored \(passed)/\(Self.cases.count)")
    }

    private static func passes(_ reply: ToolReply?, _ expect: Expect) -> Bool {
        switch (reply, expect) {
        case (.text?, .unsupported):
            return true
        case (.call(let call)?, _):
            guard call.name == "open", let kind = call.arguments["kind"], let target = call.arguments["target"] else { return false }
            switch expect {
            case .app(let name): return kind == "app" && AppResolver.match(target, in: apps) == name
            case .website(let hosts): return kind == "website" && WebsiteResolver.url(for: target)?.host().map(hosts.contains) == true
            case .folder(let folder): return kind == "folder" && FolderResolver.folder(for: target) == folder
            case .file(let word): return ["file", "folder"].contains(kind) && FileSearcher.words(in: target).contains(word)
            case .unsupported: return false
            }
        default:
            return false
        }
    }
}
```

- [ ] **Step 2: Confirm it is skipped by default.** Run the full suite. Expected: all pass, and `AgentEvalTests` is reported as skipped.

- [ ] **Step 3: Run it against the live models.**

```bash
TEST_RUNNER_VEYRA_EVAL=1 xcodebuild test -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS' -only-testing:VeyraTests/AgentEvalTests 2>&1 | grep -E "\[eval\]|✗|passed|failed"
```

  Expected: both models ≥ 90% (≥ 24/26). If a model falls below, read the ✗ lines. If a resolver rule is wrong, for example a host spelling, fix the rule with a pure test first in Task 4's suite. If the model is wrong, record the score in the ledger and continue. The spec's success criterion is then unmet and goes in the final report.

- [ ] **Step 4: Commit.** `git add -A && git commit -m "Add an opt-in evaluation of agent tool calls"`

---

### Task 8: Documentation and manual verification

**Files:**
- Modify: `README.md`, `docs/VISION.md`, `AGENTS.md`

- [ ] **Step 1: README.**
  - Add a feature bullet after **Voice commands**:

```markdown
- **Actions** — hold **Fn + Control** and say "open Slack", "open github dot com" or "open my resume".
```

  - Add `| Act | Hold **Control**, then hold **Fn**, speak, release |` after the Dictate row of the Usage table.
  - After the Voice commands section, add:

````markdown
### Actions

Hold **Control**, then hold **Fn** while you speak, and Veyra does what you ask instead of typing it. The overlay shows a ⚡ while it listens.

| Say | Opens |
|---|---|
| "open Slack", "open V S code" | An installed app |
| "open github dot com", "open YouTube" | A website, in your default browser |
| "open my downloads", "open the desktop" | Desktop, Documents, Downloads, Home, Pictures, Music or Movies |
| "open my resume", "open the Veyra project folder" | The best-matching file or folder in your home folder, most recently used first |

When several files match, Veyra opens the best one and tells you how many others matched. Actions need [Ollama](#6-transcript-cleanup-optional) with `gemma4`. The first file search may ask for access to your Documents, Desktop or Downloads folder.
````

  - Add a troubleshooting row: `| An action says "Actions need Ollama running" | Open Ollama and check that \`ollama list\` shows \`gemma4:latest\`. |`
  - Add a line to the Development diagram block:

```text
Fn+⌃ ─► … ─► WhisperKitTranscriber ─► AgentRunner ─► OllamaClient (tools) ─► OpenTool ─► NSWorkspace
```

  - Add the eval command under Development:

```bash
TEST_RUNNER_VEYRA_EVAL=1 xcodebuild test -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS' -only-testing:VeyraTests/AgentEvalTests   # needs Ollama
```

- [ ] **Step 2: Roadmap.**
  - In `docs/VISION.md` Phase 8, check `Tool abstraction`, `Tool calling` and `Safety boundaries`.
  - Below the Phase 8 list, add: `Sub-projects: 8.1 open apps, websites, folders and files (done) · 8.2 rewrite selected text · 8.3 shell commands · 8.4 send and multi-step plans · 8.5 evaluation (started).`
  - In `AGENTS.md`, replace `- [ ] Agent actions` with `- [ ] Agent actions (8.1 open apps, websites, folders and files done)`.

- [ ] **Step 3: Build and install.** `./scripts/install.sh`

- [ ] **Step 4: Manual checks.** Hold Control, then Fn:
  - "open Slack"
  - "open V S code"
  - "open github dot com"
  - "open my downloads"
  - "open my resume", with the Documents prompt if shown
  - "what's the weather", which should give the unsupported message
  - with Ollama quit: "open Slack", which should say "Actions need Ollama running"
  - plain Fn dictation, which should be unchanged

- [ ] **Step 5: Commit.** `git add -A && git commit -m "Document actions and mark Phase 8.1 done"`
