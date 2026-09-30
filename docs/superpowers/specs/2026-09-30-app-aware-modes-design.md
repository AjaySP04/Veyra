# App-Aware Modes — Design

**Date:** 2026-09-30
**Status:** Approved in conversation, pending spec review
**Sub-project:** 3 of the Veyra roadmap (Phase 6 — Context Engineering)

## Goal

Transcript cleanup adapts to the app you are dictating into:

- **Email** is formatted as an email.
- **Chat** stays short and casual.
- **Editors** keep technical terms exact.
- **Terminals** always get one safe paragraph.

The app is the one that was frontmost when you pressed Fn. It is recognized from its bundle ID, or from the window title for web apps in a browser, such as Gmail, Google Chat and Slack.

## Success Criteria

- **Mail** turns "hi john um thanks for sending the contract … thanks ajay" into a greeting line, paragraphs, and a "Thanks,\nAjay" sign-off.
- **Slack, Teams, WhatsApp, Messages**, or a Google Chat or Slack browser tab, keep "yeah i'm gonna be like five minutes late" casual. Nothing becomes an email, and bullets appear only for an announced or numbered list.
- **VS Code, Xcode, TextEdit and Notes** keep "async", "JSON", "API", "user ID" and "TODO" exact.
- **Terminal, Ghostty, iTerm and Warp** never receive a line break or a bullet, even for a dictated list and even when every cleanup model fails.
- **Any other app** gets exactly today's behaviour.
- **Nothing is invented.** Veyra never adds a greeting, sign-off, or name the speaker did not say, and `CleanupGuard` still enforces this.
- **Logs record the mode only.** They never contain the window title, which can hold email addresses or chat names.

## Non-Goals

- Shell command generation from speech (Phase 7 voice commands).
- User-configurable app lists or per-app prompts (Phase 9 settings).
- Reading the focused text field's contents or role.
- Detecting the recipient, thread, or tone of the conversation.
- New permissions. Window titles come through the Accessibility access Veyra already has.

## Decisions

| Topic | Decision | Reason |
|---|---|---|
| When the app is read | At the Fn press, when recording starts | It's the app the user is looking at while speaking, and the paste lands there too |
| Detection | Bundle ID table first. For unmapped apps (browsers, Chrome web apps), exact site-name segments of the focused window title | The owner uses both desktop apps and browser tabs |
| Terminal behaviour | Safe prose. Normal cleanup, then the code collapses the result to one line | The owner dictates prose to Claude Code in Ghostty. A line break in a shell can run a command, and code enforces this rule instead of trusting the model |
| Mode rules | One sentence appended to the proven cleanup prompt per mode. `.standard` adds nothing | Benchmarked on both models (see below). Unknown apps are unchanged |
| Interface change | `TextProcessing.process(_:mode:)` | The mode is dictation context, and the processor stays free of AppKit |

### Benchmark (`gemma4:latest` local, `gemma4:cloud`)

| Mode | Sample | Result on both models |
|---|---|---|
| Email | "hi john um thanks for sending the contract … thanks ajay" | "Hi John,\n\nThanks for sending the contract over. …\n\nThanks,\nAjay" |
| Email | "so the meeting is moved to thursday at three …" | One sentence, with no invented greeting |
| Chat | "yeah i'm gonna be like five minutes late um start without me" | "Yeah, I'm gonna be … late. Start without me." |
| Chat | "a few things first fix the login bug second update the docs" | Lead-in line plus bullets |
| Editor | "… async … json … user id … api key" | "async", "JSON", "user ID", "API" |
| Terminal | A dictated three-item list | One sentence, with no bullets |

Warm local latency was 0.9–1.5 s, and the cloud took 0.5–1.0 s. One cloud chat reply turned "I need to buy milk eggs bread and coffee" into bare bullets. The existing guard rejects it because 50% of the meaningful words are missing, so the raw text is pasted.

## Architecture

```
Fn pressed ─► DictationCoordinator.beginRecording
                 mode = DictationMode(contextProvider.current())
                 Logger: "Mode <mode>"
Fn released ─► transcribe ─► processor.process(transcript, mode: mode) ─► insert
                                    │
                                    ▼
                  OllamaTextProcessor: CleanupPrompt.system(for: mode) → guard
                                       → mode.finalize(text)   (terminal: one line)
```

### File Layout

```
Services/System/AppContext.swift               AppContext + AppContextProviding
Services/System/FrontmostAppContextProvider.swift  NSWorkspace + Accessibility window title
Features/Dictation/DictationMode.swift         enum, resolve from AppContext, finalize(_:)
Services/Text/TextProcessing.swift             process(_:mode:)
Services/Text/CleanupPrompt.swift              system(for:) with per-mode rules
Services/Text/OllamaTextProcessor.swift        passes mode, finalizes every return path
Features/Dictation/DictationCoordinator.swift  captures the mode at recording start
App/AppDependencies.swift                      wires FrontmostAppContextProvider
VeyraTests/DictationModeTests.swift
VeyraTests/CleanupPromptTests.swift            (extended)
VeyraTests/OllamaTextProcessorTests.swift      (extended)
VeyraTests/DictationCoordinatorTests.swift     (extended)
VeyraTests/Fakes.swift                         FakeAppContextProvider, updated UppercasingProcessor
```

### Interfaces

```swift
struct AppContext: Equatable {
    let bundleIdentifier: String?
    let windowTitle: String?
}

protocol AppContextProviding {
    func current() -> AppContext
}

enum DictationMode: String, Equatable {
    case email, chat, editor, terminal, standard

    init(_ context: AppContext)
    func finalize(_ text: String) -> String
}

protocol TextProcessing {
    func process(_ text: String, mode: DictationMode) async throws -> String
}

enum CleanupPrompt {
    static func system(for mode: DictationMode) -> String
    static func userMessage(for transcript: String) -> String
    static func reply(from content: String) -> String
}
```

## Component Behavior

**FrontmostAppContextProvider.current()**
- Reads the bundle ID from `NSWorkspace.shared.frontmostApplication`.
- Reads the window title through `AXUIElementCreateApplication(pid)`, first `kAXFocusedWindowAttribute`, then `kAXTitleAttribute`.
- Any failure (no frontmost app, Accessibility denied, no focused window, a non-string title) yields `nil` for that field. It never throws.

**DictationMode.init(_:)** resolves in this order.

1. **Bundle ID, exact match.**

   | Mode | Bundle IDs |
   |---|---|
   | email | `com.apple.mail`, `com.microsoft.Outlook`, `com.readdle.SparkDesktop`, `com.readdle.smartemail-Mac` |
   | chat | `com.tinyspeck.slackmacgap`, `com.microsoft.teams2`, `com.microsoft.teams`, `net.whatsapp.WhatsApp`, `com.apple.MobileSMS`, `com.hnc.Discord`, `ru.keepcoder.Telegram` |
   | editor | `com.microsoft.VSCode`, `com.apple.dt.Xcode`, `com.todesktop.230313mzl4w4u92` (Cursor), `dev.zed.Zed`, `com.sublimetext.4`, `com.apple.TextEdit`, `com.apple.Notes`, and any ID with the prefix `com.jetbrains.` |
   | terminal | `com.apple.Terminal`, `com.mitchellh.ghostty`, `com.googlecode.iterm2`, `dev.warp.Warp-Stable` |

2. **Window title**, used only when the bundle ID is unmapped or missing.
   - Split the title on ` - `, ` – `, ` — ` and ` | `.
   - Trim each segment and remove a leading unread counter such as `(3) `.
   - Compare segments case-insensitively against site names:

     | Mode | Site names |
     |---|---|
     | email | `Gmail`, `Outlook` |
     | chat | `Google Chat`, `Slack`, `WhatsApp`, `Discord`, `Microsoft Teams`, `Messenger` |

   - Whole segments are compared, so a Gmail subject such as "Slack invite" doesn't count as Slack, because the segment is "Slack invite".
   - Segments are scanned from last to first, and the first match wins, because browsers put the site name last. "Slack - Gmail" is email.
3. **Otherwise `.standard`.**

**DictationMode.finalize(_:)**
- `.terminal`: removes a leading `- `, `* ` or `• ` from every line, joins the lines with single spaces, and collapses repeated whitespace.
- **Every other mode:** returns the text unchanged.

**CleanupPrompt.system(for:)** is today's prompt (the base rules and list rule) followed by the mode rule, then `Output only the cleaned text.`

| Mode | Rule |
|---|---|
| email | "This is an email. Put a spoken greeting on its own line ending with a comma, split separate topics into paragraphs separated by a blank line, and put a spoken sign-off (such as thanks, regards, cheers) and any name after it on their own lines at the end. Never add a greeting, sign-off, or name the speaker did not say." |
| chat | "This is a chat message. Keep it short and conversational, keep casual words such as gonna and yeah, and never add a greeting, sign-off, or email structure. Use bullet points only when the speaker numbers the items or announces a list." |
| editor | "This is written in a code or text editor. Keep technical terms, names, and identifiers exactly as spoken, such as async, JSON, API, and user ID." |
| terminal | "This goes into a terminal. Output one paragraph with no line breaks and no bullet points, even for lists." |
| standard | no rule (exactly today's prompt) |

**OllamaTextProcessor.process(_:mode:)**
- Same model chain, guard and fallbacks as today.
- The request uses `CleanupPrompt.system(for: mode)`.
- Every return path goes through `mode.finalize`: the accepted reply, the raw transcript after every model fails, and a transcript with no words.

**DictationCoordinator**
- Gains a `contextProvider: AppContextProviding` dependency.
- `beginRecording` sets `mode = DictationMode(contextProvider.current())` and logs `Mode <rawValue>`.
- `transcribeAndInsert` calls `processor.process(transcript, mode: mode)`.
- A mode captured at one press is never reused for a later press.

## Error Handling

| Condition | Result |
|---|---|
| Accessibility is denied or the title can't be read | Title is `nil`, so the mode comes from the bundle ID only, else `.standard` |
| Veyra's own menu is frontmost | Unmapped, so `.standard` |
| The app switches between press and release | The mode from the press is used, and the paste goes to the now-frontmost app as today |
| The cleanup model breaks mode rules (bullets in terminal) | `finalize` flattens it anyway |
| Every model fails in terminal mode | The raw transcript is flattened, then pasted |

## Testing

All tests use Swift Testing and never touch AppKit windows, the network, or Ollama.

- **DictationModeTests** (table-driven):
  - every mapped bundle ID, plus a JetBrains prefix;
  - Gmail, Outlook, Google Chat, Slack and "(3) WhatsApp" browser titles;
  - "Slack invite - me@x.com - Gmail" resolves to email;
  - the unknown app `com.example.App` with an unrelated title;
  - a nil bundle ID with a nil title;
  - a mapped bundle ID wins over a conflicting title;
  - "Slack - Gmail" resolves to email (last segment wins);
  - `finalize` for terminal flattens a bulleted multi-line reply, and leaves other modes unchanged.
- **CleanupPromptTests:**
  - each mode's prompt contains its rule;
  - `.standard` equals today's prompt text;
  - every prompt still contains the `<transcript>` instruction and the list rule, and ends with "Output only the cleaned text."
- **OllamaTextProcessorTests:**
  - the request's system prompt matches the mode;
  - a bulleted reply in terminal mode is flattened;
  - the raw fallback in terminal mode is flattened;
  - email mode returns multi-line replies unchanged.
- **DictationCoordinatorTests:**
  - a `FakeAppContextProvider` returning a Slack context leads to the processor receiving `.chat`;
  - changing the fake's context after the press doesn't change the mode used for that dictation.
- **Manual check:**
  - dictate the benchmark samples into Mail, a Gmail tab, a Google Chat tab, VS Code and Ghostty;
  - the log shows the expected `Mode …` line for each.

## Docs

- **README:** a "Modes" row in Usage and a short table of apps per mode.
- **AGENTS.md:** the App-aware modes roadmap item is checked.
- **docs/VISION.md:** these Phase 4, 5 and 6 items are checked:
  - Phase 4: "Active application detection".
  - Phase 5: "Formatting".
  - Phase 6: "Detect active application", "Application-specific prompts", "Developer mode", "Email mode", "Chat mode" and "Terminal mode".
