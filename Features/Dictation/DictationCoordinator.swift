import Foundation
import Observation
import os

@Observable
final class DictationCoordinator {
    private static let minimumSampleCount = Int(AudioFormat.sampleRate * 0.3)
    private static let silenceLevel: Float = 0.1

    private(set) var state: DictationState = .preparing(progress: nil)
    @ObservationIgnored private(set) var transcription: Task<Void, Never>?
    @ObservationIgnored private(set) var recovery: Task<Void, Never>?
    @ObservationIgnored private var context = CommandContext(mode: .standard, bundleIdentifier: nil)
    @ObservationIgnored private var lastInsertion: LastInsertion?

    private let audio: AudioCapturing
    private let transcriber: Transcribing
    private let processor: TextProcessing
    private let inserter: TextInserting
    private let keystrokes: KeystrokeSending
    private let hotkey: HotkeyMonitoring
    private let permissions: PermissionChecking
    private let contextProvider: AppContextProviding
    private let failureDisplayDuration: Duration

    init(
        audio: AudioCapturing,
        transcriber: Transcribing,
        processor: TextProcessing,
        inserter: TextInserting,
        keystrokes: KeystrokeSending,
        hotkey: HotkeyMonitoring,
        permissions: PermissionChecking,
        contextProvider: AppContextProviding,
        failureDisplayDuration: Duration = .seconds(2)
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.processor = processor
        self.inserter = inserter
        self.keystrokes = keystrokes
        self.hotkey = hotkey
        self.permissions = permissions
        self.contextProvider = contextProvider
        self.failureDisplayDuration = failureDisplayDuration
    }

    func start() async {
        hotkey.handler = { [weak self] event in self?.handle(event) }
        audio.levelHandler = { [weak self] level in self?.updateLevel(level) }
        hotkey.start()
        await prepareModel()
    }

    func prepareModel() async {
        state = .preparing(progress: nil)
        do {
            try await transcriber.prepare { [weak self] progress in self?.updateProgress(progress) }
            state = .idle
        } catch {
            state = .unavailable(message: error.localizedDescription)
        }
    }

    func reconnectHotkey() {
        hotkey.start()
    }

    func handle(_ event: HotkeyEvent) {
        switch (event, state) {
        case (.pressed, .idle): beginRecording()
        case (.released, .recording): finishRecording()
        case (.cancelled, .recording): cancelRecording()
        case (.userInput, _): lastInsertion = nil
        default: break
        }
    }

    private func beginRecording() {
        if let missing = Permission.allCases.first(where: { !permissions.isGranted($0) }) {
            return fail("\(missing.title) access is required")
        }
        do {
            try audio.start()
            state = .recording(level: 0)
            context = CommandContext(contextProvider.current())
            Logger.dictation.info("Mode \(self.context.mode.rawValue, privacy: .public)")
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func finishRecording() {
        let samples = audio.stop()
        Logger.dictation.info("Clip \(samples.count) samples, level \(AudioLevel.normalized(samples))")
        guard isWorthTranscribing(samples) else {
            Logger.dictation.info("Clip skipped as too short or silent")
            state = .idle
            return
        }
        state = .transcribing
        transcription = Task { [context = self.context] in await transcribeAndRoute(samples, in: context) }
    }

    private func cancelRecording() {
        _ = audio.stop()
        lastInsertion = nil
        state = .idle
    }

    private func transcribeAndRoute(_ samples: [Float], in context: CommandContext) async {
        do {
            let transcript = try await transcriber.transcribe(samples)
            Logger.dictation.info("Transcript \(transcript.count) characters")
            switch Intent(transcript) {
            case .command(let command):
                return run(command, in: context)
            case .dictate(let text) where !text.isEmpty:
                let processed = try await processor.process(text, mode: context.mode)
                try await inserter.insert(processed)
                lastInsertion = LastInsertion(characterCount: processed.count, bundleIdentifier: context.bundleIdentifier)
            case .dictate:
                break
            }
            state = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func run(_ command: VoiceCommand, in context: CommandContext) {
        Logger.dictation.info("Command \(command.rawValue, privacy: .public)")
        let plan = command.plan(in: context, after: lastInsertion)
        lastInsertion = nil
        switch plan {
        case .keys(let chords):
            keystrokes.send(chords)
            state = .idle
        case .unavailable(let message):
            fail(message)
        }
    }

    private func fail(_ message: String) {
        Logger.dictation.error("\(message, privacy: .public)")
        state = .failed(message: message)
        recovery = Task { [failureDisplayDuration] in
            try? await Task.sleep(for: failureDisplayDuration)
            if state == .failed(message: message) { state = .idle }
        }
    }

    private func isWorthTranscribing(_ samples: [Float]) -> Bool {
        samples.count >= Self.minimumSampleCount && AudioLevel.normalized(samples) > Self.silenceLevel
    }

    private func updateLevel(_ level: Float) {
        if case .recording = state { state = .recording(level: level) }
    }

    private func updateProgress(_ progress: Double) {
        if case .preparing = state { state = .preparing(progress: progress) }
    }
}
