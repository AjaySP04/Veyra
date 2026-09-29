# Core Dictation Loop — Design

**Date:** 2026-09-30
**Status:** Approved in conversation, pending spec review
**Sub-project:** 1 of the Veyra roadmap (covers README Phases 1–4 minimum path)

## Goal

Wispr Flow–style dictation for personal use with no usage limits: hold **Fn**, speak, release, and the transcribed text is inserted at the cursor of whatever app is focused. Fully local and offline after the one-time model download.

## Success Criteria

- Works in any text field (Slack, Notes, VS Code, browser, Terminal).
- Transcript appears within ~1–2 s of releasing Fn for a typical 5–15 s utterance on Apple Silicon.
- No network access after the model is downloaded.
- The user's clipboard content is restored after insertion.
- Code follows SOLID/DRY: each type has one responsibility, depends on protocols, and needs minimal comments to be understood.

## Non-Goals (v1)

- LLM cleanup/formatting (sub-project 2 — plugs into `TextProcessing`).
- Hands-free/toggle mode, custom hotkeys, model picker, transcript history.
- Streaming/partial transcription, VAD.
- App Store distribution.

## Decisions

| Topic | Decision | Reason |
|---|---|---|
| Architecture | Protocol-based pipeline driven by one `DictationCoordinator` state machine, dependencies injected from a composition root | SOLID, testable with fakes, matches README's modular principle |
| Trigger | Hold Fn = record, release = transcribe + insert | Chosen by user; mirrors Wispr Flow |
| Speech model | WhisperKit, `large-v3-turbo` | Near-best accuracy with fast Apple Silicon inference |
| Insertion | Clipboard + synthetic ⌘V, then restore previous clipboard | Works in every app; unicode-safe; fast for long text |
| Sandbox | Disabled | Synthetic key events and global key monitoring are blocked in the sandbox; personal app |
| UI | `MenuBarExtra` + floating non-activating overlay pill while recording/transcribing | Unobtrusive, never steals focus from the target app |

## Architecture

```
Fn down/up ─► HotkeyMonitoring ─► DictationCoordinator ─► AudioCapturing   (start / stop → [Float] @16 kHz mono)
                                          │              ─► Transcribing    ([Float] → String)
                                          │              ─► TextProcessing  (String → String)
                                          │              ─► TextInserting   (String → focused app)
                                          ▼
                                   DictationState ─► MenuBarView, RecordingOverlay
```

### File Layout

```
App/
  VeyraApp.swift                      MenuBarExtra scene; owns AppDependencies
  AppDependencies.swift               Composition root: builds concrete services and the coordinator
Features/Dictation/
  DictationState.swift
  DictationCoordinator.swift
  MenuBarView.swift
  RecordingOverlay.swift              SwiftUI pill view + NSPanel controller
Services/
  Audio/AudioCapturing.swift          protocol
  Audio/AudioRecorder.swift           AVAudioEngine implementation (replaces current stub)
  Audio/AudioResampler.swift          AVAudioConverter → 16 kHz mono Float32
  Speech/Transcribing.swift           protocol
  Speech/WhisperKitTranscriber.swift
  Text/TextProcessing.swift           protocol + PassthroughTextProcessor
  System/HotkeyMonitoring.swift       protocol + HotkeyEvent
  System/FnKeyMonitor.swift
  System/TextInserting.swift          protocol
  System/PasteboardTextInserter.swift
  System/Pasteboard.swift             thin protocol over NSPasteboard (testability)
  System/KeystrokeSending.swift       protocol + CGEventKeystrokeSender (⌘V)
  System/PermissionService.swift
```

`Features/Dictation/ContentView.swift` is removed (replaced by `MenuBarView`).

### Interfaces

```swift
protocol AudioCapturing: AnyObject {
    var levelHandler: ((Float) -> Void)? { get set }   // normalized 0...1 RMS for the overlay meter
    func start() throws
    func stop() -> [Float]                              // 16 kHz mono samples since start
}

protocol Transcribing: Sendable {
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

protocol TextProcessing: Sendable {
    func process(_ text: String) async throws -> String
}

protocol TextInserting {
    func insert(_ text: String) async throws
}

enum HotkeyEvent { case pressed, released }

protocol HotkeyMonitoring: AnyObject {
    var handler: ((HotkeyEvent) -> Void)? { get set }
    func start()
    func stop()
}
```

### State Machine

```swift
enum DictationState: Equatable {
    case preparing(progress: Double)   // model download/load
    case idle
    case recording(level: Float)
    case transcribing
    case failed(message: String)
}
```

| From | Event | To | Action |
|---|---|---|---|
| `preparing` | model ready | `idle` | — |
| `preparing` | load error | `failed` | show error; menu offers Retry |
| `idle` | Fn pressed | `recording` | `audio.start()` |
| `recording` | Fn released | `transcribing` | `audio.stop()`; if < 0.3 s of audio → `idle` |
| `transcribing` | text ready | `idle` | trim; if empty skip; else process → insert |
| any active | error | `failed` | auto-return to `idle` after 2 s |
| `preparing` / `transcribing` / `failed` | Fn pressed | unchanged | ignored |

`DictationCoordinator` is `@MainActor @Observable`, receives all dependencies through its initializer, and contains no framework-specific code.

## Component Behavior

**AudioRecorder** — Installs a tap on `AVAudioEngine.inputNode` in the hardware format, converts each buffer through `AudioResampler` to 16 kHz mono Float32, appends to an internal buffer (serial-queue guarded), and reports RMS level. `stop()` removes the tap, stops the engine, and returns and clears the samples.

**WhisperKitTranscriber** — `prepare` downloads (first launch, cached afterward in WhisperKit's default location) and loads `large-v3-turbo`, reporting progress. `transcribe` runs WhisperKit on the samples with language auto-detect and returns joined segment text. The exact WhisperKit model identifier and API signatures are verified against the current WhisperKit release during planning.

**PassthroughTextProcessor** — Returns input unchanged. Ollama processor replaces it in sub-project 2 with no coordinator changes.

**FnKeyMonitor** — `NSEvent` global + local monitors for `.flagsChanged`; emits `.pressed` / `.released` on transitions of `.function` only, ignoring Fn used together with other keys (e.g. Fn+arrow) by cancelling if a `.keyDown` arrives while held.

**PasteboardTextInserter** — Snapshots current pasteboard items, writes the text, sends ⌘V via `KeystrokeSending`, waits ~250 ms, restores the snapshot only if the pasteboard `changeCount` is still the one it set.

**PermissionService** — Reports microphone authorization (`AVCaptureDevice`) and Accessibility trust (`AXIsProcessTrustedWithOptions`), can prompt for each and open the relevant System Settings pane.

## UI

- **Menu bar icon:** `mic` (idle), `mic.fill` (recording), `waveform` (transcribing), `exclamationmark.triangle` (failed).
- **Menu:** status line / model download progress, permission rows with "Grant" buttons when missing, hint "Hold Fn to dictate", Quit.
- **Overlay:** borderless, non-activating `NSPanel` at bottom-center of the main screen; shows a live level bar while recording and a spinner while transcribing; hidden when idle.

## Project Configuration

- Add Swift package `https://github.com/argmaxinc/WhisperKit`.
- `ENABLE_APP_SANDBOX = NO`.
- `INFOPLIST_KEY_NSMicrophoneUsageDescription = "Veyra listens while you hold Fn to transcribe your speech."`
- `INFOPLIST_KEY_LSUIElement = YES` (menu-bar only, no Dock icon).
- User setup note (README): set *System Settings → Keyboard → Press 🌐 key to → Do Nothing* so Fn doesn't open the emoji picker or system dictation.

## Error Handling

- Missing mic/Accessibility permission: coordinator refuses to record and state becomes `failed("Microphone access needed")` etc.; menu shows grant buttons.
- Model download failure: `failed` with Retry in menu.
- Transcription/insert errors: surfaced in overlay for 2 s, then `idle`. No crash paths; no `print` debugging left in production code.

## Testing

Swift Testing in `VeyraTests`, using fakes for every protocol:

- `DictationCoordinatorTests`: happy path press → release → inserted text; short clip skipped; empty transcript not inserted; Fn ignored while preparing/transcribing; error → `failed` → `idle`; processor output is what gets inserted.
- `PasteboardTextInserterTests`: writes text, sends ⌘V, restores original contents; does not restore if clipboard changed meanwhile.
- `AudioResamplerTests`: 48 kHz stereo sine buffer → 16 kHz mono with expected frame count.

Hardware, WhisperKit inference, and real key events are exercised manually: dictate into Notes, Slack, VS Code, and Terminal.
