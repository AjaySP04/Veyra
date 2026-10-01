# Voice Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Short spoken phrases ("undo that", "scratch that", "new line", …) send key chords to the frontmost app instead of being typed.

**Architecture:** After Whisper returns, `Intent(transcript)` matches the whole normalized utterance against a fixed phrase table. A match becomes a `VoiceCommand`, and the pure `VoiceCommand.plan(in:after:)` turns it into key chords for the current mode, or an unavailable message. Unmatched text follows the existing cleanup → paste path unchanged. Synthetic key events are tagged, so the key monitor can tell user typing (which invalidates "scratch that") from Veyra's own keystrokes.

**Tech Stack:** Swift 5 mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI/AppKit, CoreGraphics `CGEvent`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-01-voice-commands-design.md`

## Global Constraints

- Matching uses the raw Whisper transcript, before `TextProcessing`. Commands never call the processor or the inserter.
- A command runs only when the whole normalized utterance is a phrase: lowercase, punctuation removed, whitespace collapsed, one leading and one trailing "please" dropped.
- Terminal mode never sends Return.
- Formatting in Editor mode is allowed only for `com.apple.TextEdit` and `com.apple.Notes`.
- Messages, verbatim: "<Title> isn't available in Terminal", "Formatting isn't available in this app", "Nothing to scratch".
- Logs record `Command <rawValue>` only. Never log the transcript.
- New files land in the existing synchronized folders (`Features/`, `Services/`, `VeyraTests/`). Do not edit `project.pbxproj`.
- Test command: `xcodebuild test -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS'`. A single suite: append `-only-testing:VeyraTests/<SuiteName>`.

## Review Focus

1. **Whisper punctuation variants** ("  Undo that... ", "Undo, that!", "New-line.") must still match. Pinned in Task 2.
2. **Grapheme counting for "scratch that"**: an insertion with emoji or accents ("👍🏽 ok") must send one ⌫ per visible character (4), not per scalar. Pinned in Task 5.
3. **Typing during transcription**: a key press while Veyra is still transcribing must not clear the insertion that lands afterwards. Pinned in Task 5.
4. **Cancelled recording** (a key pressed while Fn is held reaches the app) must clear the stored insertion. Pinned in Task 5.
5. **Phrase embedded in longer speech** ("please undo the migration", "add a new line of code") must be dictated. Pinned in Task 2.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `Services/System/KeyChord.swift` | Create | Key code plus modifier flags, with named chord constants |
| `Services/System/KeystrokeSending.swift` | Modify | `send(_ chords:)` replaces `sendPaste()`. Events are tagged with `CGEventKeystrokeSender.eventMarker` |
| `Services/System/PasteboardTextInserter.swift` | Modify | Calls `keystrokes.send([.paste])` |
| `Features/Commands/VoiceCommand.swift` | Create | The commands, their phrases, titles and phrase normalization |
| `Features/Commands/Intent.swift` | Create | `.command` or `.dictate` from a transcript |
| `Features/Commands/CommandPlan.swift` | Create | `CommandContext`, `LastInsertion`, `CommandPlan` and `VoiceCommand.plan(in:after:)` |
| `Services/System/HotkeyMonitoring.swift` | Modify | `HotkeyEvent.userInput` |
| `Services/System/FnKeyTracker.swift` | Modify | `KeyInput.mouseDown`, emitting `.userInput` |
| `Services/System/FnKeyMonitor.swift` | Modify | Mouse-down mask. Ignores Veyra-tagged events |
| `Features/Dictation/DictationCoordinator.swift` | Modify | Routes on `Intent`, runs plans, tracks `lastInsertion` |
| `App/AppDependencies.swift` | Modify | Shares one `CGEventKeystrokeSender` between the inserter and the coordinator |
| `VeyraTests/Fakes.swift` | Modify | `FakeKeystrokes` records chords |
| `VeyraTests/IntentTests.swift`, `VeyraTests/CommandPlanTests.swift` | Create | Pure-logic tests |
| `VeyraTests/FnKeyTrackerTests.swift`, `VeyraTests/DictationCoordinatorTests.swift`, `VeyraTests/PasteboardTextInserterTests.swift` | Modify | New cases |
| `README.md`, `docs/VISION.md`, `AGENTS.md` | Modify | Voice commands table and roadmap check-offs |

---

### Task 1: Key chords and tagged keystroke sending

**Files:**
- Create: `Services/System/KeyChord.swift`
- Modify: `Services/System/KeystrokeSending.swift`, `Services/System/PasteboardTextInserter.swift`, `VeyraTests/Fakes.swift`
- Test: `VeyraTests/PasteboardTextInserterTests.swift`

**Interfaces:**
- Produces: `struct KeyChord: Equatable { let key: CGKeyCode; let flags: CGEventFlags }` with the static constants listed below. `protocol KeystrokeSending { func send(_ chords: [KeyChord]) }`. `CGEventKeystrokeSender.eventMarker: Int64`. `FakeKeystrokes.sentChords: [[KeyChord]]`. `FakeKeystrokes.init(pasteboard: FakePasteboard = FakePasteboard())`.

- [ ] **Step 1: Write the failing test.** Add to `PasteboardTextInserterTests`:

```swift
    @Test func pastesWithCommandV() async throws {
        try await inserter.insert("hello")
        #expect(keystrokes.sentChords == [[.paste]])
    }
```

- [ ] **Step 2: Run it.** `xcodebuild test … -only-testing:VeyraTests/PasteboardTextInserterTests`. Expected: build failure, because `sentChords` and `.paste` don't exist.

- [ ] **Step 3: Create `Services/System/KeyChord.swift`.**

```swift
import Carbon.HIToolbox
import CoreGraphics

struct KeyChord: Equatable {
    let key: CGKeyCode
    let flags: CGEventFlags

    init(_ key: Int, _ flags: CGEventFlags = []) {
        self.key = CGKeyCode(key)
        self.flags = flags
    }

    static let paste = KeyChord(kVK_ANSI_V, .maskCommand)
    static let undo = KeyChord(kVK_ANSI_Z, .maskCommand)
    static let redo = KeyChord(kVK_ANSI_Z, [.maskCommand, .maskShift])
    static let deleteBackward = KeyChord(kVK_Delete)
    static let deleteWord = KeyChord(kVK_Delete, .maskAlternate)
    static let deleteLine = KeyChord(kVK_Delete, .maskCommand)
    static let shellDeleteWord = KeyChord(kVK_ANSI_W, .maskControl)
    static let shellDeleteLine = KeyChord(kVK_ANSI_U, .maskControl)
    static let bold = KeyChord(kVK_ANSI_B, .maskCommand)
    static let italic = KeyChord(kVK_ANSI_I, .maskCommand)
    static let underline = KeyChord(kVK_ANSI_U, .maskCommand)
    static let selectAll = KeyChord(kVK_ANSI_A, .maskCommand)
    static let selectWordBackward = KeyChord(kVK_LeftArrow, [.maskAlternate, .maskShift])
    static let lineStart = KeyChord(kVK_LeftArrow, .maskCommand)
    static let lineEnd = KeyChord(kVK_RightArrow, .maskCommand)
    static let shellLineStart = KeyChord(kVK_ANSI_A, .maskControl)
    static let shellLineEnd = KeyChord(kVK_ANSI_E, .maskControl)
    static let documentStart = KeyChord(kVK_UpArrow, .maskCommand)
    static let documentEnd = KeyChord(kVK_DownArrow, .maskCommand)
    static let returnKey = KeyChord(kVK_Return)
    static let softReturn = KeyChord(kVK_Return, .maskShift)
}
```

- [ ] **Step 4: Replace `Services/System/KeystrokeSending.swift`.**

```swift
import CoreGraphics

protocol KeystrokeSending {
    func send(_ chords: [KeyChord])
}

struct CGEventKeystrokeSender: KeystrokeSending {
    static let eventMarker: Int64 = 0x5645_5952_41

    func send(_ chords: [KeyChord]) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for chord in chords {
            for isKeyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: chord.key, keyDown: isKeyDown)
                event?.flags = chord.flags
                event?.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
```

- [ ] **Step 5: In `PasteboardTextInserter.insert`, replace `keystrokes.sendPaste()` with `keystrokes.send([.paste])`.**

- [ ] **Step 6: Update `FakeKeystrokes` in `VeyraTests/Fakes.swift`.**

```swift
@MainActor
final class FakeKeystrokes: KeystrokeSending {
    private let pasteboard: FakePasteboard
    var sideEffect: () -> Void = {}
    private(set) var pastedTexts: [String?] = []
    private(set) var sentChords: [[KeyChord]] = []

    init(pasteboard: FakePasteboard = FakePasteboard()) {
        self.pasteboard = pasteboard
    }

    func send(_ chords: [KeyChord]) {
        sentChords.append(chords)
        guard chords == [.paste] else { return }
        pastedTexts.append(pasteboard.string)
        sideEffect()
    }
}
```

- [ ] **Step 7: Run the full suite.** Expected: all pass.

- [ ] **Step 8: Commit.** `git add -A && git commit -m "Send any key chord, tagged as Veyra's own"`

---

### Task 2: Commands and intent matching

**Files:**
- Create: `Features/Commands/VoiceCommand.swift`, `Features/Commands/Intent.swift`
- Test: `VeyraTests/IntentTests.swift`

**Interfaces:**
- Produces: `enum VoiceCommand: String, CaseIterable` with cases `undo, redo, scratchThat, deleteSelection, deleteLastWord, deleteLine, bold, italic, underline, selectAll, selectLastWord, lineStart, lineEnd, documentStart, documentEnd, newLine, newParagraph`, plus `phrases: [String]`, `title: String` and `init?(phrase: String)`. `enum Intent: Equatable { case dictate(String); case command(VoiceCommand); init(_ transcript: String) }`.

- [ ] **Step 1: Write the failing tests in `VeyraTests/IntentTests.swift`.**

```swift
import Testing
@testable import Veyra

@MainActor
struct IntentTests {
    @Test(arguments: [
        ("undo", VoiceCommand.undo),
        ("undo that", .undo),
        ("redo", .redo),
        ("redo that", .redo),
        ("scratch that", .scratchThat),
        ("delete that", .deleteSelection),
        ("delete last word", .deleteLastWord),
        ("delete line", .deleteLine),
        ("bold that", .bold),
        ("italic that", .italic),
        ("underline that", .underline),
        ("select all", .selectAll),
        ("select last word", .selectLastWord),
        ("go to start of line", .lineStart),
        ("go to end of line", .lineEnd),
        ("go to top", .documentStart),
        ("go to bottom", .documentEnd),
        ("new line", .newLine),
        ("new paragraph", .newParagraph),
    ])
    func matchesPhrase(phrase: String, expected: VoiceCommand) {
        #expect(Intent(phrase) == .command(expected))
    }

    @Test(arguments: [
        "Undo that.",
        "  Undo that... ",
        "Undo, that!",
        "UNDO THAT",
        "Please undo that.",
        "Undo that, please.",
    ])
    func toleratesWhisperFormatting(transcript: String) {
        #expect(Intent(transcript) == .command(.undo))
    }

    @Test func hyphenatedPhraseMatches() {
        #expect(Intent("New-line.") == .command(.newLine))
    }

    @Test(arguments: [
        "undo the migration",
        "please undo the migration",
        "add a new line of code",
        "please",
        "please please",
        "",
        "hello world",
    ])
    func otherSpeechIsDictated(transcript: String) {
        #expect(Intent(transcript) == .dictate(transcript))
    }

    @Test func everyCommandHasAPhrase() {
        #expect(VoiceCommand.allCases.allSatisfy { !$0.phrases.isEmpty })
    }

    @Test func titleCapitalizesFirstPhrase() {
        #expect(VoiceCommand.newLine.title == "New line")
        #expect(VoiceCommand.documentStart.title == "Go to top")
    }
}
```

Note: "please please" normalizes to "", which is not a phrase, so it is dictated.

- [ ] **Step 2: Run it.** `-only-testing:VeyraTests/IntentTests`. Expected: build failure, because `Intent` is undefined.

- [ ] **Step 3: Create `Features/Commands/VoiceCommand.swift`.**

```swift
import Foundation

enum VoiceCommand: String, CaseIterable {
    case undo, redo
    case scratchThat, deleteSelection, deleteLastWord, deleteLine
    case bold, italic, underline
    case selectAll, selectLastWord
    case lineStart, lineEnd, documentStart, documentEnd
    case newLine, newParagraph

    private static let commandsByPhrase = Dictionary(
        uniqueKeysWithValues: allCases.flatMap { command in command.phrases.map { ($0, command) } }
    )

    init?(phrase: String) {
        guard let command = Self.commandsByPhrase[Self.normalized(phrase)] else { return nil }
        self = command
    }

    var phrases: [String] {
        switch self {
        case .undo: ["undo", "undo that"]
        case .redo: ["redo", "redo that"]
        case .scratchThat: ["scratch that"]
        case .deleteSelection: ["delete that"]
        case .deleteLastWord: ["delete last word"]
        case .deleteLine: ["delete line"]
        case .bold: ["bold that"]
        case .italic: ["italic that"]
        case .underline: ["underline that"]
        case .selectAll: ["select all"]
        case .selectLastWord: ["select last word"]
        case .lineStart: ["go to start of line"]
        case .lineEnd: ["go to end of line"]
        case .documentStart: ["go to top"]
        case .documentEnd: ["go to bottom"]
        case .newLine: ["new line"]
        case .newParagraph: ["new paragraph"]
        }
    }

    var title: String {
        let phrase = phrases[0]
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    private static func normalized(_ text: String) -> String {
        var words = text.lowercased()
            .replacing(#/[^a-z0-9\s]/#, with: " ")
            .split(whereSeparator: \.isWhitespace)
        if words.first == "please" { words.removeFirst() }
        if words.last == "please" { words.removeLast() }
        return words.joined(separator: " ")
    }
}
```

- [ ] **Step 4: Create `Features/Commands/Intent.swift`.**

```swift
enum Intent: Equatable {
    case dictate(String)
    case command(VoiceCommand)

    init(_ transcript: String) {
        self = VoiceCommand(phrase: transcript).map(Intent.command) ?? .dictate(transcript)
    }
}
```

- [ ] **Step 5: Run `IntentTests`.** Expected: all pass.

- [ ] **Step 6: Commit.** `git add -A && git commit -m "Recognize a whole utterance as a voice command"`

---

### Task 3: Per-mode command plans

**Files:**
- Create: `Features/Commands/CommandPlan.swift`
- Test: `VeyraTests/CommandPlanTests.swift`

**Interfaces:**
- Consumes: `VoiceCommand` (Task 2), `KeyChord` constants (Task 1), `DictationMode`, `AppContext`.
- Produces: `struct CommandContext: Equatable { let mode: DictationMode; let bundleIdentifier: String?; init(mode:bundleIdentifier:); init(_ app: AppContext) }`. `struct LastInsertion: Equatable { let characterCount: Int; let bundleIdentifier: String? }`. `enum CommandPlan: Equatable { case keys([KeyChord]); case unavailable(String) }`. `VoiceCommand.plan(in context: CommandContext, after lastInsertion: LastInsertion?) -> CommandPlan`.

- [ ] **Step 1: Write the failing tests in `VeyraTests/CommandPlanTests.swift`.**

```swift
import Testing
@testable import Veyra

@MainActor
struct CommandPlanTests {
    private let notes = "com.apple.Notes"
    private let slack = "com.tinyspeck.slackmacgap"
    private let ghostty = "com.mitchellh.ghostty"

    private func plan(_ command: VoiceCommand, _ mode: DictationMode, app: String? = nil, after insertion: LastInsertion? = nil) -> CommandPlan {
        command.plan(in: CommandContext(mode: mode, bundleIdentifier: app), after: insertion)
    }

    @Test(arguments: [
        (VoiceCommand.undo, KeyChord.undo),
        (.redo, .redo),
        (.deleteSelection, .deleteBackward),
        (.deleteLastWord, .deleteWord),
        (.deleteLine, .deleteLine),
        (.bold, .bold),
        (.italic, .italic),
        (.underline, .underline),
        (.selectAll, .selectAll),
        (.selectLastWord, .selectWordBackward),
        (.lineStart, .lineStart),
        (.lineEnd, .lineEnd),
        (.documentStart, .documentStart),
        (.documentEnd, .documentEnd),
        (.newLine, .returnKey),
    ])
    func standardModeKeys(command: VoiceCommand, chord: KeyChord) {
        #expect(plan(command, .standard) == .keys([chord]))
        #expect(plan(command, .email) == .keys([chord]))
    }

    @Test func newParagraphPressesReturnTwice() {
        #expect(plan(.newParagraph, .standard) == .keys([.returnKey, .returnKey]))
    }

    @Test func chatLineBreaksDoNotSend() {
        #expect(plan(.newLine, .chat, app: slack) == .keys([.softReturn]))
        #expect(plan(.newParagraph, .chat, app: slack) == .keys([.softReturn, .softReturn]))
        #expect(plan(.bold, .chat, app: slack) == .keys([.bold]))
    }

    @Test(arguments: [
        (VoiceCommand.undo, KeyChord.undo),
        (.redo, .redo),
        (.deleteLastWord, .shellDeleteWord),
        (.deleteLine, .shellDeleteLine),
        (.lineStart, .shellLineStart),
        (.lineEnd, .shellLineEnd),
    ])
    func terminalUsesShellKeys(command: VoiceCommand, chord: KeyChord) {
        #expect(plan(command, .terminal, app: ghostty) == .keys([chord]))
    }

    @Test(arguments: [
        VoiceCommand.deleteSelection, .bold, .italic, .underline, .selectAll, .selectLastWord,
        .documentStart, .documentEnd, .newLine, .newParagraph,
    ])
    func terminalBlocksUnsafeCommands(command: VoiceCommand) {
        #expect(plan(command, .terminal, app: ghostty) == .unavailable("\(command.title) isn't available in Terminal"))
    }

    @Test func terminalNeverSendsReturn() {
        for command in VoiceCommand.allCases {
            guard case .keys(let chords) = plan(command, .terminal, app: ghostty) else { continue }
            #expect(!chords.contains { $0.key == KeyChord.returnKey.key })
        }
    }

    @Test(arguments: ["com.apple.Notes", "com.apple.TextEdit"])
    func richTextEditorsFormat(app: String) {
        #expect(plan(.bold, .editor, app: app) == .keys([.bold]))
        #expect(plan(.italic, .editor, app: app) == .keys([.italic]))
        #expect(plan(.underline, .editor, app: app) == .keys([.underline]))
    }

    @Test(arguments: ["com.microsoft.VSCode", "com.apple.dt.Xcode", "com.jetbrains.intellij"])
    func codeEditorsBlockFormatting(app: String) {
        for command in [VoiceCommand.bold, .italic, .underline] {
            #expect(plan(command, .editor, app: app) == .unavailable("Formatting isn't available in this app"))
        }
        #expect(plan(.undo, .editor, app: app) == .keys([.undo]))
    }

    @Test func scratchDeletesEachInsertedCharacter() {
        let insertion = LastInsertion(characterCount: 3, bundleIdentifier: notes)
        #expect(plan(.scratchThat, .editor, app: notes, after: insertion) == .keys(Array(repeating: .deleteBackward, count: 3)))
    }

    @Test func scratchWorksInTerminal() {
        let insertion = LastInsertion(characterCount: 2, bundleIdentifier: ghostty)
        #expect(plan(.scratchThat, .terminal, app: ghostty, after: insertion) == .keys([.deleteBackward, .deleteBackward]))
    }

    @Test func scratchWithoutInsertionIsUnavailable() {
        #expect(plan(.scratchThat, .standard) == .unavailable("Nothing to scratch"))
    }

    @Test func scratchInAnotherAppIsUnavailable() {
        let insertion = LastInsertion(characterCount: 3, bundleIdentifier: notes)
        #expect(plan(.scratchThat, .chat, app: slack, after: insertion) == .unavailable("Nothing to scratch"))
    }

    @Test func contextReadsModeAndBundleFromApp() {
        let context = CommandContext(AppContext(bundleIdentifier: slack, windowTitle: nil))
        #expect(context == CommandContext(mode: .chat, bundleIdentifier: slack))
    }
}
```

- [ ] **Step 2: Run it.** `-only-testing:VeyraTests/CommandPlanTests`. Expected: build failure.

- [ ] **Step 3: Create `Features/Commands/CommandPlan.swift`.**

```swift
struct CommandContext: Equatable {
    let mode: DictationMode
    let bundleIdentifier: String?

    init(mode: DictationMode, bundleIdentifier: String?) {
        self.mode = mode
        self.bundleIdentifier = bundleIdentifier
    }

    init(_ app: AppContext) {
        self.init(mode: DictationMode(app), bundleIdentifier: app.bundleIdentifier)
    }
}

struct LastInsertion: Equatable {
    let characterCount: Int
    let bundleIdentifier: String?
}

enum CommandPlan: Equatable {
    case keys([KeyChord])
    case unavailable(String)
}

extension VoiceCommand {
    private static let blockedInTerminal: Set<VoiceCommand> = [
        .deleteSelection, .bold, .italic, .underline, .selectAll, .selectLastWord,
        .documentStart, .documentEnd, .newLine, .newParagraph,
    ]
    private static let formatting: Set<VoiceCommand> = [.bold, .italic, .underline]
    private static let richTextEditors: Set<String> = ["com.apple.TextEdit", "com.apple.Notes"]

    func plan(in context: CommandContext, after lastInsertion: LastInsertion?) -> CommandPlan {
        let isTerminal = context.mode == .terminal
        if isTerminal, Self.blockedInTerminal.contains(self) {
            return .unavailable("\(title) isn't available in Terminal")
        }
        if context.mode == .editor, Self.formatting.contains(self),
           !Self.richTextEditors.contains(context.bundleIdentifier ?? "") {
            return .unavailable("Formatting isn't available in this app")
        }
        let lineBreak: KeyChord = context.mode == .chat ? .softReturn : .returnKey
        switch self {
        case .undo: return .keys([.undo])
        case .redo: return .keys([.redo])
        case .scratchThat:
            guard let lastInsertion, lastInsertion.bundleIdentifier == context.bundleIdentifier else {
                return .unavailable("Nothing to scratch")
            }
            return .keys(Array(repeating: .deleteBackward, count: lastInsertion.characterCount))
        case .deleteSelection: return .keys([.deleteBackward])
        case .deleteLastWord: return .keys([isTerminal ? .shellDeleteWord : .deleteWord])
        case .deleteLine: return .keys([isTerminal ? .shellDeleteLine : .deleteLine])
        case .bold: return .keys([.bold])
        case .italic: return .keys([.italic])
        case .underline: return .keys([.underline])
        case .selectAll: return .keys([.selectAll])
        case .selectLastWord: return .keys([.selectWordBackward])
        case .lineStart: return .keys([isTerminal ? .shellLineStart : .lineStart])
        case .lineEnd: return .keys([isTerminal ? .shellLineEnd : .lineEnd])
        case .documentStart: return .keys([.documentStart])
        case .documentEnd: return .keys([.documentEnd])
        case .newLine: return .keys([lineBreak])
        case .newParagraph: return .keys([lineBreak, lineBreak])
        }
    }
}
```

- [ ] **Step 4: Run `CommandPlanTests`.** Expected: all pass.

- [ ] **Step 5: Commit.** `git add -A && git commit -m "Plan each voice command's keys for the current mode"`

---

### Task 4: Report user typing and clicks

**Files:**
- Modify: `Services/System/HotkeyMonitoring.swift`, `Services/System/FnKeyTracker.swift`, `Services/System/FnKeyMonitor.swift`
- Test: `VeyraTests/FnKeyTrackerTests.swift`

**Interfaces:**
- Consumes: `CGEventKeystrokeSender.eventMarker` (Task 1).
- Produces: `HotkeyEvent.userInput`, `KeyInput.mouseDown`.

- [ ] **Step 1: Write the failing tests.** In `FnKeyTrackerTests`, replace `keyDownWithoutFnIsIgnored` with:

```swift
    @Test func keyDownWithoutFnIsUserInput() {
        #expect(events([.keyDown]) == [.userInput])
    }

    @Test func mouseDownWithoutFnIsUserInput() {
        #expect(events([.mouseDown]) == [.userInput])
    }

    @Test func mouseDownWhileHeldIsIgnored() {
        #expect(events([fnDown, .mouseDown, fnUp]) == [.pressed, .released])
    }

    @Test func typingAfterReleaseIsUserInput() {
        #expect(events([fnDown, fnUp, .keyDown]) == [.pressed, .released, .userInput])
    }
```

`keyDownWhileHeldCancelsOnce` and `worksAgainAfterCancelledPress` stay unchanged and must still pass.

- [ ] **Step 2: Run it.** `-only-testing:VeyraTests/FnKeyTrackerTests`. Expected: build failure, because `.mouseDown` and `.userInput` don't exist.

- [ ] **Step 3: Add the event case.** In `HotkeyMonitoring.swift`, add `case userInput` after `case cancelled`.

- [ ] **Step 4: Update `FnKeyTracker.swift`.** Add `case mouseDown` to `KeyInput`, then add this case to `handle(_:)` just before `default:`:

```swift
        case .keyDown where !isHeld, .mouseDown where !isHeld:
            return .userInput
```

- [ ] **Step 5: Update `FnKeyMonitor.swift`.** Change the mask to `[.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]`, and replace the `KeyInput` extension with:

```swift
private extension KeyInput {
    init?(_ event: NSEvent) {
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != CGEventKeystrokeSender.eventMarker else {
            return nil
        }
        switch event.type {
        case .keyDown:
            self = .keyDown
        case .leftMouseDown, .rightMouseDown:
            self = .mouseDown
        case .flagsChanged:
            let flags = event.modifierFlags
            self = .flagsChanged(
                fn: flags.contains(.function),
                otherModifiers: !flags.isDisjoint(with: [.shift, .control, .option, .command])
            )
        default:
            return nil
        }
    }
}
```

- [ ] **Step 6: Run the full suite.** Expected: all pass. The coordinator's `default: break` already ignores `.userInput`.

- [ ] **Step 7: Commit.** `git add -A && git commit -m "Report the user's own typing and clicks to the coordinator"`

---

### Task 5: Route commands in the coordinator

**Files:**
- Modify: `Features/Dictation/DictationCoordinator.swift`, `App/AppDependencies.swift`
- Test: `VeyraTests/DictationCoordinatorTests.swift`

**Interfaces:**
- Consumes: `Intent`, `VoiceCommand.plan(in:after:)`, `CommandContext`, `LastInsertion`, `CommandPlan`, `KeystrokeSending.send(_:)`, `HotkeyEvent.userInput`, `FakeKeystrokes.sentChords`.
- Produces: `DictationCoordinator.init(audio:transcriber:processor:inserter:keystrokes:hotkey:permissions:contextProvider:failureDisplayDuration:)`.

- [ ] **Step 1: Update the test setup.** In `DictationCoordinatorTests`, add `private let keystrokes = FakeKeystrokes()` and pass `keystrokes: keystrokes,` after `inserter: inserter,` in `readyCoordinator`. Add a helper:

```swift
    private func say(_ transcript: String, to coordinator: DictationCoordinator) async {
        transcriber.transcript = transcript
        await dictate(coordinator)
    }
```

- [ ] **Step 2: Write the failing tests.** Append to `DictationCoordinatorTests`:

```swift
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
```

Add this to `VeyraTests/Fakes.swift`:

```swift
struct AppendingProcessor: TextProcessing {
    let suffix: String

    func process(_ text: String, mode: DictationMode) async throws -> String { text + suffix }
}
```

- [ ] **Step 3: Run it.** `-only-testing:VeyraTests/DictationCoordinatorTests`. Expected: build failure, because of the extra `keystrokes:` argument.

- [ ] **Step 4: Update `DictationCoordinator.swift`.**
  - Replace `@ObservationIgnored private var mode: DictationMode = .standard` with:

    ```swift
    @ObservationIgnored private var context = CommandContext(mode: .standard, bundleIdentifier: nil)
    @ObservationIgnored private var lastInsertion: LastInsertion?
    ```

  - Add `private let keystrokes: KeystrokeSending` after `inserter`, add the `keystrokes: KeystrokeSending,` init parameter after `inserter`, and assign it.
  - In `handle(_:)`, add `case (.userInput, _): lastInsertion = nil` before `default:`.
  - In `beginRecording()`, replace the two `mode` lines with:

    ```swift
            context = CommandContext(contextProvider.current())
            Logger.dictation.info("Mode \(self.context.mode.rawValue, privacy: .public)")
    ```

  - In `finishRecording()`, replace the task line with `transcription = Task { [context = self.context] in await transcribeAndRoute(samples, in: context) }`.
  - In `cancelRecording()`, add `lastInsertion = nil` after `_ = audio.stop()`.
  - Replace `transcribeAndInsert` with:

    ```swift
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
    ```

- [ ] **Step 5: Update `App/AppDependencies.swift`.** Before the coordinator, add `let keystrokes = CGEventKeystrokeSender()`. Pass `keystrokes: keystrokes` to `PasteboardTextInserter`, and add `keystrokes: keystrokes,` after `inserter:` in the coordinator init.

- [ ] **Step 6: Run the full suite.** Expected: all pass, including every existing coordinator test.

- [ ] **Step 7: Commit.** `git add -A && git commit -m "Run voice commands instead of typing them"`

---

### Task 6: Documentation and manual verification

**Files:**
- Modify: `README.md`, `docs/VISION.md`, `AGENTS.md`

- [ ] **Step 1: README.** Change the opening tagline paragraph's second line to "Private, unlimited voice dictation for macOS — hold **Fn**, speak, release, and your words appear wherever your cursor is. Say a command instead, and Veyra edits for you." Add a feature bullet after **Clean text**:

```markdown
- **Voice commands** — say "undo that", "scratch that" or "new line" and Veyra presses the keys for you.
```

Insert after the mode table in **Usage**:

````markdown
### Voice commands

Hold **Fn** and say one of these phrases on its own. Capitals, punctuation and a "please" are ignored. Anything else you say is typed as usual.

| Say | Does |
|---|---|
| "undo" / "undo that" | Undo |
| "redo" / "redo that" | Redo |
| "scratch that" | Removes what Veyra just typed, if you haven't typed, clicked or switched apps since |
| "delete that" | Deletes the selection |
| "delete last word" | Deletes the word before the cursor |
| "delete line" | Deletes to the start of the line |
| "bold that" / "italic that" / "underline that" | Formats the selection |
| "select all" | Selects everything |
| "select last word" | Selects the word before the cursor |
| "go to start of line" / "go to end of line" | Moves the cursor along the line |
| "go to top" / "go to bottom" | Moves to the start or end of the document |
| "new line" / "new paragraph" | Adds a line break or a blank line |

Some commands adapt to the app:

- **Chat apps:** line breaks use ⇧↩, so your message is never sent.
- **Terminals:** nothing presses Return. Word and line deletion and line moves use the shell's ⌃W, ⌃U, ⌃A and ⌃E. Selection, formatting, document moves and line breaks are unavailable.
- **Code editors:** formatting is unavailable, because ⌘B and ⌘I do other things there. Notes and TextEdit format normally.

When a command can't run, Veyra types nothing and shows why. Because a whole utterance is matched, you can't dictate just the words "undo that" as text.
````

In the Development diagram, add a second line below the existing one:

```text
                                                           └─► Intent ─► VoiceCommand.plan ─► CGEventKeystrokeSender
```

- [ ] **Step 2: Roadmap.** In `docs/VISION.md` Phase 7, check off all five items. In `AGENTS.md`, replace `- [ ] Voice commands and agent actions` with `- [x] Voice commands (undo, delete, formatting, selection and navigation)` followed by `- [ ] Agent actions`.

- [ ] **Step 3: Build and install.** `./scripts/install.sh`. Expected: Veyra launches.

- [ ] **Step 4: Manual checks on a real Mac.** Each must pass:
  - Notes: dictate a sentence, then "scratch that" removes it. "bold that" on a selection bolds it. "undo that" reverts.
  - Slack: "new line" adds a line break without sending.
  - VS Code: "bold that" shows "Formatting isn't available in this app", and the sidebar doesn't move.
  - Terminal or Ghostty: dictate, then "scratch that" removes it. "delete last word" deletes a word. "new line" shows the unavailable message and runs nothing.
  - Typing a character after a dictation, then "scratch that", shows "Nothing to scratch".

- [ ] **Step 5: Commit.** `git add -A && git commit -m "Document voice commands and mark Phase 7 done"`
