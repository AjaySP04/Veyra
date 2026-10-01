# Voice Commands — Design

**Date:** 2026-10-01
**Status:** Approved in conversation, pending spec review
**Sub-project:** 4 of the Veyra roadmap (Phase 7 — Voice Commands)

## Goal

Some short utterances act on the text in the frontmost app instead of being typed:

- **Undo and redo** what you just did.
- **Delete** the last word, the line, the selection, or Veyra's last insertion ("scratch that").
- **Format** the selection as bold, italic or underlined.
- **Select and move**: select all, select the last word, jump to the start or end of a line or document, and add a line break or paragraph.

A command is recognized when the whole utterance is one of a fixed set of phrases. Everything else is dictated exactly as today.

## Success Criteria

- Saying "undo that" in Notes undoes the last change, and nothing is typed.
- Saying "scratch that" right after a dictation removes exactly that dictation, in any app, including Terminal.
- "Scratch that" never deletes text Veyra did not insert. If you typed, clicked or switched apps since the insertion, it does nothing and says "Nothing to scratch".
- In Slack, "new line" adds a line break and never sends the message.
- In Terminal, Ghostty, iTerm and Warp, no command presses Return, so a command can never run a shell command.
- In VS Code and Xcode, "bold that" does not toggle a sidebar or open a panel. It shows "Formatting isn't available in this app".
- Commands work without Ollama and do not wait for cleanup.
- An utterance that merely contains a command phrase ("undo the migration", "add a new line of code") is dictated as text.
- Logs record the command name only. Unmatched text is never logged.

## Non-Goals

- Repeat counts ("delete last three words").
- Clipboard commands (copy, cut, paste).
- Outward-facing actions: "send", "press enter", opening apps, shell command generation (Phase 8 — Agent System).
- LLM intent classification or free-form phrasing.
- User-configurable phrases (Phase 9 settings).
- Dictating an utterance that is exactly a command phrase as literal text. This is the accepted trade-off of whole-phrase matching.

## Decisions

| Topic | Decision | Reason |
|---|---|---|
| Trigger | Same Fn hold. The whole utterance must match a known phrase | No new gesture, deterministic, no added latency, works offline |
| Match input | Raw Whisper transcript, before cleanup | Cleanup could rewrite the phrase, and commands should not wait for Ollama |
| Normalization | Lowercase, strip punctuation, collapse whitespace, drop a leading or trailing "please" | Whisper adds punctuation and capitals ("Undo that.") |
| Execution | Synthetic key chords through `KeystrokeSending` | Reuses the CGEvent path that already pastes, and works in every app |
| Mode rules | One pure function, `VoiceCommand.plan(in:after:)`, owns every per-mode mapping and block | All safety rules live in one place and are table-tested |
| Blocked command | Nothing is typed. The overlay shows a short reason through `.failed(message:)` | Typing "new line" into a terminal would be worse than doing nothing, and no new UI state is needed |
| "Scratch that" | Backspace once per inserted character, only while the insertion is still the last thing that happened in that app | Works the same in every app, including terminals where ⌘Z does not undo a paste |
| Own keystrokes | Every synthetic event is tagged through `eventSourceUserData` and ignored by the key monitor | Veyra's own paste and commands must not count as the user typing |

## Commands

| Command | Phrases | Standard / Email / Editor | Chat | Terminal |
|---|---|---|---|---|
| `undo` | "undo", "undo that" | ⌘Z | ⌘Z | ⌘Z |
| `redo` | "redo", "redo that" | ⇧⌘Z | ⇧⌘Z | ⇧⌘Z |
| `scratchThat` | "scratch that" | ⌫ × last insertion length | same | same |
| `deleteSelection` | "delete that" | ⌫ | ⌫ | blocked |
| `deleteLastWord` | "delete last word" | ⌥⌫ | ⌥⌫ | ⌃W |
| `deleteLine` | "delete line" | ⌘⌫ | ⌘⌫ | ⌃U |
| `bold` | "bold that" | ⌘B | ⌘B | blocked |
| `italic` | "italic that" | ⌘I | ⌘I | blocked |
| `underline` | "underline that" | ⌘U | ⌘U | blocked |
| `selectAll` | "select all" | ⌘A | ⌘A | blocked |
| `selectLastWord` | "select last word" | ⌥⇧← | ⌥⇧← | blocked |
| `lineStart` | "go to start of line" | ⌘← | ⌘← | ⌃A |
| `lineEnd` | "go to end of line" | ⌘→ | ⌘→ | ⌃E |
| `documentStart` | "go to top" | ⌘↑ | ⌘↑ | blocked |
| `documentEnd` | "go to bottom" | ⌘↓ | ⌘↓ | blocked |
| `newLine` | "new line" | ↩ | ⇧↩ | blocked |
| `newParagraph` | "new paragraph" | ↩ ↩ | ⇧↩ ⇧↩ | blocked |

**Formatting in Editor mode.** `bold`, `italic` and `underline` are allowed only in the rich-text editors `com.apple.TextEdit` and `com.apple.Notes`. In every other Editor-mode app (VS Code, Xcode, Cursor, Zed, Sublime Text, JetBrains IDEs) they are blocked, because ⌘B and ⌘I are bound to other actions there.

**Unavailable messages.**

| Case | Message |
|---|---|
| Blocked in Terminal mode | "<Name> isn't available in Terminal" (for example "New line isn't available in Terminal") |
| Formatting in a code editor | "Formatting isn't available in this app" |
| "Scratch that" with nothing to remove | "Nothing to scratch" |

## Architecture

```text
Fn release ─► WhisperKitTranscriber ─► Intent(transcript)
                                         ├─ .dictate(text) ─► OllamaTextProcessor ─► PasteboardTextInserter   (unchanged)
                                         └─ .command(cmd)  ─► cmd.plan(in: CommandContext, after: lastInsertion) ─► KeystrokeSending.send(_:)
                                                                └─ .unavailable(reason) ─► .failed(message:) for 2 s
```

### Units

| Unit | Location | Responsibility |
|---|---|---|
| `VoiceCommand` | `Features/Commands/VoiceCommand.swift` | The 17 commands, their phrases, and their display names |
| `Intent` | `Features/Commands/Intent.swift` | `init(_ transcript:)` normalizes text and returns `.command(VoiceCommand)` or `.dictate(String)` |
| `CommandContext`, `LastInsertion`, `CommandPlan`, `VoiceCommand.plan(in:after:)` | `Features/Commands/CommandPlan.swift` | Pure mapping from command, mode and bundle ID to key chords or an unavailable reason |
| `KeyChord` | `Services/System/KeyChord.swift` | A virtual key code plus modifier flags, with named constants |
| `KeystrokeSending.send(_:)` | `Services/System/KeystrokeSending.swift` | Posts chords as CGEvents tagged with Veyra's `eventSourceUserData` marker. `sendPaste()` becomes `send([.paste])` |
| `FnKeyTracker`, `FnKeyMonitor` | `Services/System/` | Also emit `HotkeyEvent.userInput` for a key press or mouse press while Fn is up. Veyra-tagged events are ignored |
| `DictationCoordinator` | `Features/Dictation/` | Captures the `CommandContext` at the Fn press, routes on `Intent`, and tracks `LastInsertion` |

### "Scratch that" state

The coordinator holds `lastInsertion: LastInsertion?`, where `LastInsertion` has `characterCount: Int` and `bundleIdentifier: String?`.

- **Set** after a successful paste, from the final pasted text's `count`.
- **Cleared** on `HotkeyEvent.userInput`, after any command runs (including "scratch that" itself), and when a recording is cancelled.
- **Checked** when "scratch that" runs: the bundle ID in the current `CommandContext` must equal the stored one. Otherwise the command is unavailable.

### Error handling

- A command never throws. `CGEvent` posting gives no result, and an unavailable plan is reported as a message.
- The existing permission check at the Fn press already covers Accessibility, which commands need.
- A transcription error behaves exactly as today.

### Logging

`Logger.dictation.info("Command \(command.rawValue, privacy: .public)")`. Command names come from a fixed vocabulary, so no user words are logged.

## Testing

| Suite | Covers |
|---|---|
| `IntentTests` | Every phrase. Case, punctuation and "please" variants. Non-matches stay `.dictate`: "undo the migration", "new line of code", "please", "" |
| `CommandPlanTests` | Every command in every mode. Chat ⇧↩, Terminal ⌃W, ⌃U, ⌃A, ⌃E and blocks. Formatting allowed in Notes and TextEdit, blocked in VS Code and Xcode |
| `FnKeyTrackerTests` | `userInput` is emitted for key and mouse presses while Fn is up, is never emitted while Fn is held, and keys pressed while holding Fn still cancel |
| `DictationCoordinatorTests` | A command bypasses the processor and the inserter, and the fake sender records the chords. Valid scratch, scratch after `userInput`, scratch after an app switch, double scratch, and an unavailable message |
| Manual | Notes, Slack, VS Code and Terminal on a real Mac, because synthetic key events cannot be unit-tested |

## Documentation

- README: a "Voice commands" table in Usage, listing phrases, what each does and mode exceptions, plus the whole-phrase trade-off.
- `docs/VISION.md` Phase 7 and the `AGENTS.md` roadmap are checked off when the work merges.
