import Foundation
@testable import Veyra

@MainActor
final class FakePasteboard: Pasteboard {
    static let textType = "public.utf8-plain-text"

    private(set) var changeCount = 0
    var items: [[String: Data]] = []

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
    private(set) var pastedTexts: [String?] = []

    init(pasteboard: FakePasteboard) {
        self.pasteboard = pasteboard
    }

    func sendPaste() {
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
    func process(_ text: String) async throws -> String { text.uppercased() }
}

@MainActor
final class FakeInserter: TextInserting {
    private(set) var inserted: [String] = []

    func insert(_ text: String) async throws {
        inserted.append(text)
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

    func complete(_ request: ChatRequest) async throws -> String {
        requests.append(request)
        guard let reply = replies[request.model] else { throw TestError() }
        return try reply.get()
    }
}
