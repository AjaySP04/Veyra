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
    private let agent = FakeAgent()

    private func readyCoordinator(
        processor: TextProcessing = PassthroughTextProcessor(),
        failureDisplayDuration: Duration = .seconds(60),
        confirmationTimeout: Duration = .seconds(60)
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
            agent: agent,
            isSecureInputEnabled: { [secureInput] in secureInput.isEnabled },
            failureDisplayDuration: failureDisplayDuration,
            confirmationTimeout: confirmationTimeout
        )
        await coordinator.start()
        return coordinator
    }

    private func dictate(_ coordinator: DictationCoordinator) async {
        hotkey.send(.pressed(.dictate), .released)
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
        hotkey.send(.pressed(.dictate))
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
        hotkey.send(.pressed(.dictate))
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
        hotkey.send(.pressed(.dictate), .released, .pressed(.dictate))
        #expect(coordinator.state == .transcribing)
        #expect(!audio.isRecording)
        await coordinator.transcription?.value
        #expect(inserter.inserted == ["hello world"])
        #expect(coordinator.state == .idle)
    }

    @Test func cancelDiscardsRecording() async {
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed(.dictate), .cancelled)
        #expect(!audio.isRecording)
        #expect(coordinator.state == .idle)
        #expect(transcriber.receivedSamples == nil)
    }

    @Test func missingPermissionBlocksRecording() async {
        permissions.denied = [.accessibility]
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed(.dictate))
        #expect(!audio.isRecording)
        #expect(coordinator.state == .failed(message: "Accessibility access is required"))
    }

    @Test func audioStartErrorShowsFailure() async {
        audio.startError = TestError()
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed(.dictate))
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
        hotkey.send(.pressed(.dictate))
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
        hotkey.send(.pressed(.dictate))
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
        hotkey.send(.pressed(.dictate), .released, .userInput)
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
        hotkey.send(.pressed(.dictate), .cancelled)
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
        hotkey.send(.pressed(.dictate), .released)
        context.context = AppContext(bundleIdentifier: "com.mitchellh.ghostty", windowTitle: nil)
        await coordinator.transcription?.value
        #expect(keystrokes.sentChords.isEmpty)
        #expect(coordinator.state == .failed(message: "Command cancelled because the app changed"))
    }
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
        await say("hello world", to: coordinator)
        #expect(inserter.inserted == ["hello world"])
        #expect(agent.transcripts == ["Open Slack."])
    }

    @Test func fnWorksWhileAnActionResultIsShowing() async {
        let coordinator = await readyCoordinator()
        await act("Open Slack.", on: coordinator)
        #expect(coordinator.state == .acted(message: "Opened Slack"))
        hotkey.send(.pressed(.dictate))
        #expect(coordinator.state == .recording(level: 0))
        #expect(coordinator.gesture == .dictate)
    }

    @Test func fnWorksWhileAFailureIsShowing() async {
        agent.outcome = .failed("No app called “Foo”")
        let coordinator = await readyCoordinator()
        await act("open foo", on: coordinator)
        hotkey.send(.pressed(.act))
        #expect(coordinator.state == .recording(level: 0))
    }

    @Test func actionReceivesTheValidLastInsertion() async {
        context.context = AppContext(bundleIdentifier: "com.apple.Notes", windowTitle: nil)
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await dictate(coordinator)
        await act("make that shorter", on: coordinator)
        #expect(agent.contexts.map(\.lastInsertion) == [LastInsertion(text: "hello world", bundleIdentifier: "com.apple.Notes")])
        #expect(agent.contexts.map(\.mode) == [.editor])
    }

    @Test func actionDoesNotReceiveAnInsertionAfterTyping() async {
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await dictate(coordinator)
        hotkey.send(.userInput)
        await act("make that shorter", on: coordinator)
        #expect(agent.contexts.map(\.lastInsertion) == [nil])
    }

    @Test func actionDoesNotReceiveAnInsertionUnderSecureInput() async {
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await dictate(coordinator)
        secureInput.isEnabled = true
        await act("make that shorter", on: coordinator)
        #expect(agent.contexts.map(\.lastInsertion) == [nil])
    }

    @Test func failedActionKeepsTheLastDictation() async {
        agent.outcome = .failed("I can open things, rewrite text, write commands and send messages for now")
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await dictate(coordinator)
        await act("do something odd", on: coordinator)
        await coordinator.recovery?.value
        await act("make that shorter", on: coordinator)
        #expect(agent.contexts.map(\.lastInsertion?.text) == ["hello world", "hello world"])
    }

    @Test func failedActionAfterTypingDropsTheLastDictation() async {
        agent.outcome = .failed("Select some text first")
        agent.onRun = { [hotkey] in hotkey.send(.userInput) }
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await dictate(coordinator)
        await act("make that shorter", on: coordinator)
        await coordinator.recovery?.value
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func runningACommandEndsScratchThat() async {
        context.context = AppContext(bundleIdentifier: "com.mitchellh.ghostty", windowTitle: nil)
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await dictate(coordinator)
        await say("run it", to: coordinator)
        await coordinator.recovery?.value
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords == [[.returnKey]])
    }

    @Test func actionInsertionCanBeScratched() async {
        agent.outcome = .done("Rewrote your last dictation", insertion: LastInsertion(text: "Hi.", bundleIdentifier: nil))
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await act("make that shorter", on: coordinator)
        await coordinator.recovery?.value
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords == [Array(repeating: .deleteBackward, count: 3)])
    }

    @Test func typingDuringAnActionDropsItsInsertion() async {
        agent.outcome = .done("Rewrote your last dictation", insertion: LastInsertion(text: "Hi.", bundleIdentifier: nil))
        agent.onRun = { [hotkey] in hotkey.send(.userInput) }
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await act("make that shorter", on: coordinator)
        await coordinator.recovery?.value
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func actionContextReportsTypingDuringTheAction() async {
        agent.onRun = { [hotkey] in hotkey.send(.userInput) }
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await act("make that shorter", on: coordinator)
        #expect(agent.contexts.map { $0.isUntouched() } == [false])
    }

    @Test func untouchedActionContextStaysValid() async {
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await act("make that shorter", on: coordinator)
        #expect(agent.contexts.map { $0.isUntouched() } == [true])
    }

    @Test func fnKeyDuringAnActionCountsAsInput() async {
        agent.outcome = .done("Rewrote your last dictation", insertion: LastInsertion(text: "Hi.", bundleIdentifier: nil))
        agent.onRun = { [hotkey] in hotkey.send(.cancelled) }
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await act("make that shorter", on: coordinator)
        #expect(agent.contexts.map { $0.isUntouched() } == [false])
        await coordinator.recovery?.value
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    // MARK: Slash commands

    @Test func spokenSlashCommandIsTypedInATerminal() async {
        context.context = AppContext(bundleIdentifier: "com.mitchellh.ghostty", windowTitle: nil)
        let coordinator = await readyCoordinator(processor: UppercasingProcessor())
        await say("Slash compact.", to: coordinator)
        await say("Slash handoff, write it for the send branch.", to: coordinator)
        #expect(inserter.inserted == ["/compact", "/handoff WRITE IT FOR THE SEND BRANCH."])
    }

    @Test func spokenSlashIsOrdinaryTextOutsideATerminal() async {
        context.context = AppContext(bundleIdentifier: "com.apple.Notes", windowTitle: nil)
        let coordinator = await readyCoordinator(processor: UppercasingProcessor())
        await say("Slash compact.", to: coordinator)
        #expect(inserter.inserted == ["SLASH COMPACT."])
    }

    // MARK: Confirmed send

    private let slack = AppContext(bundleIdentifier: "com.tinyspeck.slackmacgap", windowTitle: nil)
    private let prompt = "Say “send it” to send"

    private func draft(on coordinator: DictationCoordinator, in app: AppContext? = nil, failing error: Error? = nil) async {
        context.context = app ?? slack
        let confirmation = Confirmation(done: "Sent", failure: "Couldn't send") { [keystrokes] in
            if let error { throw error }
            keystrokes.send([.returnKey])
        }
        agent.outcome = .awaiting(
            prompt,
            insertion: LastInsertion(text: "Sounds good", bundleIdentifier: slack.bundleIdentifier),
            confirmation: confirmation
        )
        await act("reply sounds good", on: coordinator)
    }

    @Test func draftWaitsForConfirmation() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        #expect(coordinator.state == .awaiting(message: prompt))
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func sayingSendItSends() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        await say("Send it.", to: coordinator)
        #expect(keystrokes.sentChords == [[.returnKey]])
        #expect(coordinator.state == .acted(message: "Sent"))
    }

    @Test func sendsOnlyOnce() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        await say("send it", to: coordinator)
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords == [[.returnKey]])
        #expect(coordinator.state == .failed(message: "Nothing to send"))
    }

    @Test func sendItWithNothingPendingPressesNothing() async {
        context.context = slack
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
        #expect(coordinator.state == .failed(message: "Nothing to send"))
    }

    @Test func typingCancelsTheSend() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        hotkey.send(.userInput)
        #expect(coordinator.state == .idle)
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func switchingAppsCancelsTheSend() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        context.context = AppContext(bundleIdentifier: "com.apple.Notes", windowTitle: nil)
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
        #expect(coordinator.state == .failed(message: "Cancelled because the app changed"))
    }

    @Test func cancelKeepsTheDraftAndSendsNothing() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        await say("Don't send.", to: coordinator)
        #expect(coordinator.state == .acted(message: "Not sent"))
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func cancelWithNothingPending() async {
        let coordinator = await readyCoordinator()
        await say("cancel", to: coordinator)
        #expect(coordinator.state == .failed(message: "Nothing to cancel"))
    }

    @Test func otherDictationCancelsTheSend() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        await say("hello world", to: coordinator)
        await say("send it", to: coordinator)
        #expect(inserter.inserted == ["hello world"])
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func anotherActionCancelsTheSend() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        agent.outcome = .done("Opened Slack")
        await act("open slack", on: coordinator)
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func scratchThatDeletesTheDraftAndCancels() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords == [Array(repeating: .deleteBackward, count: 11)])
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.count == 1)
    }

    @Test func aSentMessageCannotBeScratched() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        await say("send it", to: coordinator)
        await say("scratch that", to: coordinator)
        #expect(keystrokes.sentChords == [[.returnKey]])
    }

    @Test func timeoutCancelsTheSend() async {
        let coordinator = await readyCoordinator(confirmationTimeout: .zero)
        await draft(on: coordinator)
        await coordinator.confirmationExpiry?.value
        #expect(coordinator.state == .idle)
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func timeoutDoesNotHideANewerState() async {
        let coordinator = await readyCoordinator(confirmationTimeout: .milliseconds(50))
        await draft(on: coordinator)
        hotkey.send(.pressed(.dictate))
        await coordinator.confirmationExpiry?.value
        #expect(coordinator.state == .recording(level: 0))
    }

    @Test func fnWorksWhileWaitingToSend() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        hotkey.send(.pressed(.dictate))
        #expect(coordinator.state == .recording(level: 0))
    }

    @Test func tooShortClipKeepsWaitingToSend() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        audio.samples = [0.1]
        hotkey.send(.pressed(.dictate), .released)
        #expect(coordinator.state == .awaiting(message: prompt))
    }

    @Test func confirmFailureIsShown() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator, failing: AgentError.interrupted)
        await say("send it", to: coordinator)
        #expect(coordinator.state == .failed(message: "Cancelled because you typed"))
    }

    @Test func clickingWhileSayingSendItCancelsTheSend() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        transcriber.transcript = "send it"
        hotkey.send(.pressed(.dictate), .userInput, .released)
        await coordinator.transcription?.value
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func switchingBrowserTabsCancelsTheSend() async {
        let coordinator = await readyCoordinator()
        await draft(on: coordinator, in: AppContext(bundleIdentifier: "com.google.Chrome", windowTitle: "Inbox - Gmail"))
        context.context = AppContext(bundleIdentifier: "com.google.Chrome", windowTitle: "Sign up - Example")
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
        #expect(coordinator.state == .failed(message: "Cancelled because the app changed"))
    }

    @Test func failedRecordingCancelsTheSend() async {
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await draft(on: coordinator)
        transcriber.transcribeError = TestError()
        await dictate(coordinator)
        await coordinator.recovery?.value
        #expect(coordinator.state == .idle)
        transcriber.transcribeError = nil
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }

    @Test func typingWhileDraftingDropsTheSend() async {
        agent.onRun = { [hotkey] in hotkey.send(.userInput) }
        let coordinator = await readyCoordinator()
        await draft(on: coordinator)
        #expect(coordinator.state == .failed(message: "Cancelled because you typed"))
        await say("send it", to: coordinator)
        #expect(keystrokes.sentChords.isEmpty)
    }
}
