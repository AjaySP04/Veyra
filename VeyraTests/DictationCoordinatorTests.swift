import Testing
@testable import Veyra

@MainActor
struct DictationCoordinatorTests {
    private let audio = FakeAudio()
    private let transcriber = FakeTranscriber()
    private let inserter = FakeInserter()
    private let keystrokes = FakeKeystrokes()
    private let hotkey = FakeHotkey()
    private let permissions = FakePermissions()
    private let context = FakeAppContextProvider()
    private let secureInput = FakeSecureInput()

    private func readyCoordinator(
        processor: TextProcessing = PassthroughTextProcessor(),
        failureDisplayDuration: Duration = .seconds(60)
    ) async -> DictationCoordinator {
        let coordinator = DictationCoordinator(
            audio: audio,
            transcriber: transcriber,
            processor: processor,
            inserter: inserter,
            keystrokes: keystrokes,
            hotkey: hotkey,
            permissions: permissions,
            contextProvider: context,
            isSecureInputEnabled: { [secureInput] in secureInput.isEnabled },
            failureDisplayDuration: failureDisplayDuration
        )
        await coordinator.start()
        return coordinator
    }

    private func dictate(_ coordinator: DictationCoordinator) async {
        hotkey.send(.pressed, .released)
        await coordinator.transcription?.value
    }

    private func say(_ transcript: String, to coordinator: DictationCoordinator) async {
        transcriber.transcript = transcript
        await dictate(coordinator)
    }

    @Test func becomesIdleWhenModelIsReady() async {
        let coordinator = await readyCoordinator()
        #expect(coordinator.state == .idle)
        #expect(hotkey.startCount == 1)
    }

    @Test func modelFailureMakesDictationUnavailable() async {
        transcriber.prepareError = TestError()
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed)
        #expect(coordinator.state == .unavailable(message: "boom"))
        #expect(!audio.isRecording)
    }

    @Test func retryAfterModelFailure() async {
        transcriber.prepareError = TestError()
        let coordinator = await readyCoordinator()
        transcriber.prepareError = nil
        await coordinator.prepareModel()
        #expect(coordinator.state == .idle)
    }

    @Test func lateProgressDoesNotLeaveIdle() async {
        let coordinator = await readyCoordinator()
        transcriber.progressHandler?(0.9)
        #expect(coordinator.state == .idle)
    }

    @Test func pressStartsRecordingAndReportsLevel() async {
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed)
        audio.levelHandler?(0.7)
        #expect(audio.isRecording)
        #expect(coordinator.state == .recording(level: 0.7))
    }

    @Test func levelIgnoredWhenNotRecording() async {
        let coordinator = await readyCoordinator()
        audio.levelHandler?(0.7)
        #expect(coordinator.state == .idle)
    }

    @Test func dictationInsertsTranscript() async {
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(inserter.inserted == ["hello world"])
        #expect(coordinator.state == .idle)
    }

    @Test func insertsProcessedText() async {
        let coordinator = await readyCoordinator(processor: UppercasingProcessor())
        await dictate(coordinator)
        #expect(inserter.inserted == ["HELLO WORLD"])
    }

    @Test func longDictationPassesEverySample() async {
        audio.samples = Array(repeating: 0.1, count: 16_000 * 120)
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(transcriber.receivedSamples?.count == 16_000 * 120)
    }

    @Test func shortClipIsNotTranscribed() async {
        audio.samples = Array(repeating: 0.1, count: 1_000)
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(transcriber.receivedSamples == nil)
        #expect(coordinator.state == .idle)
    }

    @Test func silentClipIsNotTranscribed() async {
        audio.samples = Array(repeating: 0, count: 16_000)
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(transcriber.receivedSamples == nil)
        #expect(inserter.inserted.isEmpty)
    }

    @Test func emptyTranscriptIsNotInserted() async {
        transcriber.transcript = ""
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(inserter.inserted.isEmpty)
        #expect(coordinator.state == .idle)
    }

    @Test func pressWhileTranscribingIsIgnored() async {
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed, .released, .pressed)
        #expect(coordinator.state == .transcribing)
        #expect(!audio.isRecording)
        await coordinator.transcription?.value
        #expect(inserter.inserted == ["hello world"])
        #expect(coordinator.state == .idle)
    }

    @Test func cancelDiscardsRecording() async {
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed, .cancelled)
        #expect(!audio.isRecording)
        #expect(coordinator.state == .idle)
        #expect(transcriber.receivedSamples == nil)
    }

    @Test func missingPermissionBlocksRecording() async {
        permissions.denied = [.accessibility]
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed)
        #expect(!audio.isRecording)
        #expect(coordinator.state == .failed(message: "Accessibility access is required"))
    }

    @Test func audioStartErrorShowsFailure() async {
        audio.startError = TestError()
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed)
        #expect(coordinator.state == .failed(message: "boom"))
    }

    @Test func transcriptionErrorShowsFailure() async {
        transcriber.transcribeError = TestError()
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(coordinator.state == .failed(message: "boom"))
        #expect(inserter.inserted.isEmpty)
    }

    @Test func failureReturnsToIdle() async {
        transcriber.transcribeError = TestError()
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await dictate(coordinator)
        await coordinator.recovery?.value
        #expect(coordinator.state == .idle)
    }

    @Test func reconnectHotkeyRestartsMonitor() async {
        let coordinator = await readyCoordinator()
        coordinator.reconnectHotkey()
        #expect(hotkey.startCount == 2)
    }

    @Test func processorReceivesModeOfAppAtPress() async {
        let processor = RecordingProcessor()
        context.context = AppContext(bundleIdentifier: "com.tinyspeck.slackmacgap", windowTitle: nil)
        let coordinator = await readyCoordinator(processor: processor)
        await dictate(coordinator)
        #expect(processor.modes == [.chat])
    }

    @Test func switchingAppsAfterPressKeepsPressMode() async {
        let processor = RecordingProcessor()
        context.context = AppContext(bundleIdentifier: "com.mitchellh.ghostty", windowTitle: nil)
        let coordinator = await readyCoordinator(processor: processor)
        hotkey.send(.pressed)
        context.context = AppContext(bundleIdentifier: "com.apple.mail", windowTitle: nil)
        hotkey.send(.released)
        await coordinator.transcription?.value
        #expect(processor.modes == [.terminal])
    }

    @Test func eachPressReadsTheCurrentApp() async {
        let processor = RecordingProcessor()
        let coordinator = await readyCoordinator(processor: processor)
        context.context = AppContext(bundleIdentifier: "com.google.Chrome", windowTitle: "Inbox - Gmail")
        await dictate(coordinator)
        context.context = AppContext(bundleIdentifier: "com.mitchellh.ghostty", windowTitle: nil)
        await dictate(coordinator)
        #expect(processor.modes == [.email, .terminal])
    }

    @Test func recordingStartsBeforeAppContextIsRead() async {
        var recordingWhenRead: Bool?
        context.onRead = { [audio] in recordingWhenRead = audio.isRecording }
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed)
        #expect(recordingWhenRead == true)
        #expect(coordinator.state == .recording(level: 0))
    }

    @Test func commandSendsKeysWithoutProcessingOrInserting() async {
        let processor = RecordingProcessor()
        let coordinator = await readyCoordinator(processor: processor)
        await say("Undo that.", to: coordinator)
        #expect(keystrokes.sentChords == [[.undo]])
        #expect(processor.modes.isEmpty)
        #expect(inserter.inserted.isEmpty)
        #expect(coordinator.state == .idle)
    }

    @Test func commandUsesModeOfAppAtPress() async {
        context.context = AppContext(bundleIdentifier: "com.tinyspeck.slackmacgap", windowTitle: nil)
        let coordinator = await readyCoordinator()
        await say("New line", to: coordinator)
        #expect(keystrokes.sentChords == [[.softReturn]])
    }

    @Test func unavailableCommandShowsReasonAndTypesNothing() async {
        context.context = AppContext(bundleIdentifier: "com.mitchellh.ghostty", windowTitle: nil)
        let coordinator = await readyCoordinator()
        await say("New line.", to: coordinator)
        #expect(coordinator.state == .failed(message: "New line isn't available in Terminal"))
        #expect(keystrokes.sentChords.isEmpty)
        #expect(inserter.inserted.isEmpty)
    }

    @Test func scratchThatDeletesLastInsertion() async {
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        await say("Scratch that.", to: coordinator)
        #expect(keystrokes.sentChords == [Array(repeating: .deleteBackward, count: "hello world".count)])
    }

    @Test func scratchCountsVisibleCharacters() async {
        let coordinator = await readyCoordinator()
        await say("👍🏽 ok", to: coordinator)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords == [Array(repeating: .deleteBackward, count: 4)])
    }

    @Test func scratchCountsProcessedText() async {
        let coordinator = await readyCoordinator(processor: AppendingProcessor(suffix: "!!"))
        await dictate(coordinator)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords == [Array(repeating: .deleteBackward, count: "hello world!!".count)])
    }

    @Test func scratchTwiceDeletesOnlyOnce() async {
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        await say("scratch that", to: coordinator)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.count == 1)
        #expect(coordinator.state == .failed(message: "Nothing to scratch"))
    }

    @Test func typingAfterInsertionPreventsScratch() async {
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        hotkey.send(.userInput)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
        #expect(coordinator.state == .failed(message: "Nothing to scratch"))
    }

    @Test func typingDuringTranscriptionKeepsTheNewInsertion() async {
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed, .released, .userInput)
        await coordinator.transcription?.value
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords == [Array(repeating: .deleteBackward, count: "hello world".count)])
    }

    @Test func switchingAppsPreventsScratch() async {
        context.context = AppContext(bundleIdentifier: "com.apple.Notes", windowTitle: nil)
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        context.context = AppContext(bundleIdentifier: "com.tinyspeck.slackmacgap", windowTitle: nil)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func otherCommandPreventsScratch() async {
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        await say("undo", to: coordinator)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords == [[.undo]])
    }

    @Test func cancelledRecordingPreventsScratch() async {
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        hotkey.send(.pressed, .cancelled)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func typingWhileTheInsertionLandsPreventsScratch() async {
        let coordinator = await readyCoordinator()
        inserter.onInsert = { [hotkey] in hotkey.send(.userInput) }
        await dictate(coordinator)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
        #expect(coordinator.state == .failed(message: "Nothing to scratch"))
    }

    @Test func secureInputAtScratchPreventsIt() async {
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        secureInput.isEnabled = true
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
        #expect(coordinator.state == .failed(message: "Nothing to scratch"))
    }

    @Test func secureInputAtInsertionPreventsScratch() async {
        secureInput.isEnabled = true
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        secureInput.isEnabled = false
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func appSwitchBeforeCommandRunsCancelsIt() async {
        context.context = AppContext(bundleIdentifier: "com.apple.Notes", windowTitle: nil)
        let coordinator = await readyCoordinator()
        transcriber.transcript = "new line"
        hotkey.send(.pressed, .released)
        context.context = AppContext(bundleIdentifier: "com.mitchellh.ghostty", windowTitle: nil)
        await coordinator.transcription?.value
        #expect(keystrokes.sentChords.isEmpty)
        #expect(coordinator.state == .failed(message: "Command cancelled because the app changed"))
    }
}
