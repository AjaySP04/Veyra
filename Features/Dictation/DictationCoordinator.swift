import Carbon.HIToolbox
import Foundation
import Observation
import os

@Observable
final class DictationCoordinator {
    /// A drafted send waiting for "send it", tied to the app and mode it was drafted in. A browser's mode comes from its tab title, so another tab cancels it.
    private struct PendingSend {
        let id = UUID()
        let prompt: String
        let context: CommandContext
        let confirmation: Confirmation
    }

    private static let minimumSampleCount = Int(AudioFormat.sampleRate * 0.3)
    private static let silenceLevel: Float = 0.1

    private(set) var state: DictationState = .preparing(progress: nil)
    private(set) var gesture: Gesture = .dictate
    @ObservationIgnored private(set) var transcription: Task<Void, Never>?
    @ObservationIgnored private(set) var recovery: Task<Void, Never>?
    @ObservationIgnored private(set) var confirmationExpiry: Task<Void, Never>?
    @ObservationIgnored private var pendingSend: PendingSend?
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
    private let confirmationTimeout: Duration

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
        failureDisplayDuration: Duration = .seconds(2),
        confirmationTimeout: Duration = .seconds(60)
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
        self.confirmationTimeout = confirmationTimeout
    }

    func start() async {
        hotkey.handler = { [weak self] event in self?.handle(event) }
        audio.levelHandler = { [weak self] level in self?.updateLevel(level) }
        hotkey.start()
        await prepareModel()
    }

    func prepareModel() async {
        cancelPendingSend("reloaded")
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
        case (.pressed(let gesture), .idle), (.pressed(let gesture), .acted),
             (.pressed(let gesture), .failed), (.pressed(let gesture), .awaiting):
            beginRecording(gesture)
        case (.released, .recording): finishRecording()
        case (.cancelled, .recording): cancelRecording()
        case (.cancelled, _), (.userInput, _):
            userInputCount += 1
            lastInsertion = nil
            cancelPendingSend("typed")
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
            state = restingState
            return
        }
        state = .transcribing
        transcription = Task { [context = self.context, gesture = self.gesture] in
            switch gesture {
            case .dictate: await transcribeAndRoute(samples, in: context)
            case .act: await transcribeAndAct(samples, in: context)
            }
        }
    }

    private func cancelRecording() {
        _ = audio.stop()
        lastInsertion = nil
        cancelPendingSend("typed")
        state = .idle
    }

    private func transcribeAndRoute(_ samples: [Float], in context: CommandContext) async {
        do {
            let transcript = try await transcriber.transcribe(samples)
            Logger.dictation.info("Transcript \(transcript.count) characters")
            let intent = Intent(transcript)
            if intent != .command(.send), intent != .command(.cancelSend), intent != .dictate("") {
                cancelPendingSend("replaced")
            }
            switch intent {
            case .command(let command):
                return await run(command, in: context)
            case .dictate(let text) where !text.isEmpty:
                let processed: String
                if context.mode == .terminal, let slash = SlashCommand(text) {
                    // The command itself skips cleanup so it's typed exactly; only what follows is cleaned.
                    Logger.dictation.info("Slash command")
                    let rest = slash.rest.isEmpty ? "" : try await processor.process(slash.rest, mode: context.mode)
                    processed = SlashCommand(command: slash.command, rest: rest).text
                } else {
                    processed = try await processor.process(text, mode: context.mode)
                }
                let inputCountBeforeInsert = userInputCount
                try await inserter.insert(processed)
                let isUntouched = userInputCount == inputCountBeforeInsert && !isSecureInputEnabled()
                lastInsertion = isUntouched
                    ? LastInsertion(text: processed, bundleIdentifier: context.bundleIdentifier)
                    : nil
            case .dictate:
                return state = restingState
            }
            state = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func transcribeAndAct(_ samples: [Float], in context: CommandContext) async {
        do {
            let transcript = try await transcriber.transcribe(samples)
            guard !transcript.isEmpty else {
                state = restingState
                return
            }
            cancelPendingSend("replaced")
            state = .acting
            let insertion = isSecureInputEnabled() || lastInsertion?.bundleIdentifier != context.bundleIdentifier ? nil : lastInsertion
            lastInsertion = nil
            let inputCountBeforeAction = userInputCount
            let toolContext = ToolContext(
                mode: context.mode, bundleIdentifier: context.bundleIdentifier, lastInsertion: insertion,
                isUntouched: { [weak self] in
                    guard let self else { return false }
                    return userInputCount == inputCountBeforeAction && !isSecureInputEnabled()
                }
            )
            switch await agent.run(transcript, in: toolContext) {
            case .done(let message, let newInsertion):
                lastInsertion = userInputCount == inputCountBeforeAction ? newInsertion : nil
                showBriefly(.acted(message: message))
            case .awaiting(let message, let newInsertion, let confirmation):
                guard userInputCount == inputCountBeforeAction else {
                    lastInsertion = nil
                    return showBriefly(.failed(message: AgentError.interrupted.message))
                }
                lastInsertion = newInsertion
                awaitConfirmation(PendingSend(prompt: message, context: context, confirmation: confirmation))
            case .failed(let message):
                // A failed or misheard action leaves the text where it was, so "scratch that" and rewrites still apply to it.
                lastInsertion = userInputCount == inputCountBeforeAction ? insertion : nil
                showBriefly(.failed(message: message))
            }
        } catch {
            lastInsertion = nil
            fail(error.localizedDescription)
        }
    }

    private func run(_ command: VoiceCommand, in context: CommandContext) async {
        Logger.dictation.info("Command \(command.rawValue, privacy: .public)")
        let insertion = isSecureInputEnabled() ? nil : lastInsertion
        lastInsertion = nil
        guard contextProvider.current().bundleIdentifier == context.bundleIdentifier else {
            cancelPendingSend("app-changed")
            return fail("Command cancelled because the app changed")
        }
        if command == .send || command == .cancelSend, let pending = takePendingSend() {
            guard command == .send else {
                Logger.agent.info("Send cancelled")
                return showBriefly(.acted(message: "Not sent"))
            }
            return await confirm(pending)
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

    private var restingState: DictationState {
        pendingSend.map { .awaiting(message: $0.prompt) } ?? .idle
    }

    private func awaitConfirmation(_ pending: PendingSend) {
        pendingSend = pending
        state = .awaiting(message: pending.prompt)
        confirmationExpiry = Task { [confirmationTimeout] in
            try? await Task.sleep(for: confirmationTimeout)
            guard !Task.isCancelled, pendingSend?.id == pending.id else { return }
            cancelPendingSend("expired")
        }
    }

    private func takePendingSend() -> PendingSend? {
        defer {
            pendingSend = nil
            confirmationExpiry?.cancel()
        }
        return pendingSend
    }

    /// Drops a pending send; the draft stays where it is. Only the waiting prompt is cleared, never a newer state.
    private func cancelPendingSend(_ reason: String) {
        guard takePendingSend() != nil else { return }
        Logger.agent.info("Send cancelled: \(reason, privacy: .public)")
        if case .awaiting = state { state = .idle }
    }

    private func confirm(_ pending: PendingSend) async {
        guard CommandContext(contextProvider.current()) == pending.context else {
            Logger.agent.info("Send cancelled: app-changed")
            return fail(AgentError.appChanged.message)
        }
        state = .acting
        do {
            try await pending.confirmation.perform()
            Logger.agent.info("Send confirmed")
            showBriefly(.acted(message: pending.confirmation.done))
        } catch {
            Logger.agent.info("Send failed")
            showBriefly(.failed(message: (error as? AgentError)?.message ?? pending.confirmation.failure))
        }
    }

    private func fail(_ message: String) {
        cancelPendingSend("failed")
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
