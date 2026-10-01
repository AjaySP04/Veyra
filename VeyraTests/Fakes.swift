import Foundation
@testable import Veyra

@MainActor
final class FakePasteboard: Pasteboard {
    static let textType = "public.utf8-plain-text"

    private(set) var changeCount = 0
    var items: [[String: Data]] = []

    func readText() -> String? { string }

    var string: String? {
        items.first?[Self.textType].flatMap { String(data: $0, encoding: .utf8) }
    }

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: items)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        items = snapshot.items
        changeCount += 1
    }

    func write(_ text: String) {
        items = [[Self.textType: Data(text.utf8)]]
        changeCount += 1
    }
}

@MainActor
final class FakeKeystrokes: KeystrokeSending {
    private let pasteboard: FakePasteboard
    var sideEffect: () -> Void = {}
    var onSend: ([KeyChord]) -> Void = { _ in }
    private(set) var pastedTexts: [String?] = []
    private(set) var sentChords: [[KeyChord]] = []

    init(pasteboard: FakePasteboard) {
        self.pasteboard = pasteboard
    }

    convenience init() {
        self.init(pasteboard: FakePasteboard())
    }

    func send(_ chords: [KeyChord]) {
        sentChords.append(chords)
        onSend(chords)
        guard chords == [.paste] else { return }
        pastedTexts.append(pasteboard.string)
        sideEffect()
    }
}

struct TestError: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
final class FakeAudio: AudioCapturing {
    var levelHandler: ((Float) -> Void)?
    var samples: [Float] = Array(repeating: 0.1, count: 16_000)
    var startError: Error?
    private(set) var isRecording = false

    func start() throws {
        if let startError { throw startError }
        isRecording = true
    }

    func stop() -> [Float] {
        isRecording = false
        return samples
    }
}

@MainActor
final class FakeTranscriber: Transcribing {
    var transcript = "hello world"
    var prepareError: Error?
    var transcribeError: Error?
    private(set) var receivedSamples: [Float]?
    private(set) var progressHandler: (@MainActor (Double) -> Void)?

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        progressHandler = progress
        if let prepareError { throw prepareError }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        receivedSamples = samples
        if let transcribeError { throw transcribeError }
        return transcript
    }
}

struct UppercasingProcessor: TextProcessing {
    func process(_ text: String, mode: DictationMode) async throws -> String { text.uppercased() }
}

@MainActor
final class FakeInserter: TextInserting {
    private(set) var inserted: [String] = []
    var onInsert: () -> Void = {}

    func insert(_ text: String) async throws {
        inserted.append(text)
        onInsert()
    }
}

@MainActor
final class FakeHotkey: HotkeyMonitoring {
    var handler: ((HotkeyEvent) -> Void)?
    private(set) var startCount = 0

    func start() { startCount += 1 }
    func stop() {}

    func send(_ events: HotkeyEvent...) {
        events.forEach { handler?($0) }
    }
}

@MainActor
final class FakePermissions: PermissionChecking {
    var denied: Set<Permission> = []

    func isGranted(_ permission: Permission) -> Bool { !denied.contains(permission) }
}

@MainActor
final class FakeChatCompleter: ChatCompleting {
    var replies: [String: Result<String, Error>] = [:]
    private(set) var requests: [ChatRequest] = []
    private(set) var warmedUpModels: [String] = []

    func warmUp(_ model: String) {
        warmedUpModels.append(model)
    }

    func complete(_ request: ChatRequest) async throws -> String {
        requests.append(request)
        guard let reply = replies[request.model] else { throw TestError() }
        return try reply.get()
    }
}

@MainActor
final class FakeAppContextProvider: AppContextProviding {
    var context = AppContext(bundleIdentifier: nil, windowTitle: nil)
    var onRead: () -> Void = {}

    func current() -> AppContext {
        onRead()
        return context
    }
}

@MainActor
final class RecordingProcessor: TextProcessing {
    private(set) var modes: [DictationMode] = []

    func process(_ text: String, mode: DictationMode) async throws -> String {
        modes.append(mode)
        return text
    }
}

struct AppendingProcessor: TextProcessing {
    let suffix: String

    func process(_ text: String, mode: DictationMode) async throws -> String { text + suffix }
}

@MainActor
final class FakeSecureInput {
    var isEnabled = false
}

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
    var insertion: LastInsertion?
    private(set) var preparedArguments: [[String: String]] = []
    private(set) var contexts: [ToolContext] = []
    private(set) var performCount = 0

    func prepare(_ arguments: [String: String], in context: ToolContext) async throws -> PreparedAction {
        preparedArguments.append(arguments)
        contexts.append(context)
        if let prepareError { throw prepareError }
        return PreparedAction(done: "Opened Slack", failure: "Couldn't open Slack", insertion: insertion) { [self] in
            performCount += 1
            if let performError { throw performError }
        }
    }
}

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

@MainActor
final class FakeAgent: AgentRunning {
    var outcome = AgentOutcome.done("Opened Slack")
    var onRun: () -> Void = {}
    private(set) var transcripts: [String] = []
    private(set) var contexts: [ToolContext] = []

    func run(_ transcript: String, in context: ToolContext) async -> AgentOutcome {
        transcripts.append(transcript)
        contexts.append(context)
        onRun()
        return outcome
    }
}

struct FakeSelectionReader: SelectionReading {
    var read = SelectionRead.unknown
    func selectedText() -> SelectionRead { read }
}

@MainActor
final class FakeCopier: SelectionCopying {
    var copied: String?
    private(set) var copyCount = 0

    func copySelection() async -> String? {
        copyCount += 1
        return copied
    }
}

@MainActor
final class FakeRewriter: TextRewriting {
    var result: Result<String, Error> = .success("Rewritten.")
    private(set) var calls: [(text: String, instruction: String)] = []

    func rewrite(_ text: String, instruction: String) async throws -> String {
        calls.append((text, instruction))
        return try result.get()
    }
}
