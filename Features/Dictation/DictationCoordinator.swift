import Carbon.HIToolbox
import Foundation
import Observation
import os

@Observable
final class DictationCoordinator {
    private static let minimumSampleCount = Int(AudioFormat.sampleRate * 0.3)
    private static let silenceLevel: Float = 0.1

    private(set) var state: DictationState = .preparing(progress: nil)
    private(set) var gesture: Gesture = .dictate
    @ObservationIgnored private(set) var transcription: Task<Void, Never>?
    @ObservationIgnored private(set) var recovery: Task<Void, Never>?
    @ObservationIgnored private var context = CommandContext(mode: .standard, bundleIdentifier: nil)
    @ObservationIgnored private var lastInsertion: LastInsertion?
    @ObservationIgnored private var userInputCount = 0

    private let audio: AudioCapturing
    private let transcriber: Transcribing
    private let processor: TextProcessing
    private let inserter: TextInserting
    private let keystrokes: KeystrokeSending
    private let hotkey: HotkeyMonitoring
    private let permissions: PermissionChecking
    private let contextProvider: AppContextProviding
    private let agent: AgentRunning
    private let isSecureInputEnabled: () -> Bool
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
        agent: AgentRunning,
        isSecureInputEnabled: @escaping () -> Bool = { IsSecureEventInputEnabled() },
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
        self.agent = agent
        self.isSecureInputEnabled = isSecureInputEnabled
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
        case (.pressed(let gesture), .idle), (.pressed(let gesture), .acted), (.pressed(let gesture), .failed):
            beginRecording(gesture)
        case (.released, .recording): finishRecording()
        case (.cancelled, .recording): cancelRecording()
        case (.userInput, _):
            userInputCount += 1
            lastInsertion = nil
        default: break
        }
    }

    private func beginRecording(_ gesture: Gesture) {
        if let missing = Permission.allCases.first(where: { !permissions.isGranted($0) }) {
            return fail("\(missing.title) access is required")
        }
        do {
            try audio.start()
            state = .recording(level: 0)
            self.gesture = gesture
            context = CommandContext(contextProvider.current())
            Logger.dictation.info("Mode \(self.context.mode.rawValue, privacy: .public), gesture \(gesture == .act ? "act" : "dictate", privacy: .public)")
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
        transcription = Task { [context = self.context, gesture = self.gesture] in
            switch gesture {
            case .dictate: await transcribeAndRoute(samples, in: context)
            case .act: await transcribeAndAct(samples)
            }
        }
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
                let inputCountBeforeInsert = userInputCount
                try await inserter.insert(processed)
                let isUntouched = userInputCount == inputCountBeforeInsert && !isSecureInputEnabled()
                lastInsertion = isUntouched
                    ? LastInsertion(characterCount: processed.count, bundleIdentifier: context.bundleIdentifier)
                    : nil
            case .dictate:
                break
            }
            state = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

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

    private func run(_ command: VoiceCommand, in context: CommandContext) {
        Logger.dictation.info("Command \(command.rawValue, privacy: .public)")
        let insertion = isSecureInputEnabled() ? nil : lastInsertion
        lastInsertion = nil
        guard contextProvider.current().bundleIdentifier == context.bundleIdentifier else {
            return fail("Command cancelled because the app changed")
        }
        let plan = command.plan(in: context, after: insertion)
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
        showBriefly(.failed(message: message))
    }

    private func showBriefly(_ shown: DictationState) {
        state = shown
        recovery = Task { [failureDisplayDuration] in
            try? await Task.sleep(for: failureDisplayDuration)
            if state == shown { state = .idle }
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
