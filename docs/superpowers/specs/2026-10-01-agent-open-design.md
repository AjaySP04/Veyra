# Agent Foundation and "Open" — Design

**Date:** 2026-10-01
**Status:** Approved in conversation, pending spec review
**Sub-project:** 8.1 of the Veyra roadmap (Phase 8 — Agent System)

## Goal

Hold **Fn + Control** and ask Veyra to open something, and it does:

- **Apps:** "open Slack", "open V S code".
- **Websites:** "open github dot com", "open YouTube".
- **Standard folders:** "open my downloads".
- **Any file or folder by name:** "open my resume", "open the Veyra project folder".

This sub-project also builds the foundation that the rest of Phase 8 extends:

- the action gesture
- the tool abstraction
- local-first LLM tool calling
- an agent runner
- the risk rule every tool follows
- a starter evaluation suite

## Phase 8 Decomposition

| # | Sub-project | Status |
|---|---|---|
| 8.1 | Agent foundation and opening apps, websites, folders and files | This spec |
| 8.2 | Rewrite selected text ("make this formal", "summarize", "translate") | Later |
| 8.3 | Shell commands written into the terminal, never run | Later |
| 8.4 | Send and submit with confirmation, multi-step plans, agent state | Later |
| 8.5 | Agent evaluation | Starter suite in 8.1, grows with each sub-project |

## Success Criteria

- Holding Fn with Control already down and saying "open Slack" opens Slack, and the overlay says "Opened Slack".
- Holding plain Fn behaves exactly as today, including Phase 7 voice commands. Dictation gets no added latency.
- "Open V S code" opens Visual Studio Code, "open github dot com" opens https://github.com in the default browser, and "open my downloads" opens Downloads in Finder.
- "Open my resume" opens the most relevant, most recently used file whose name contains "resume". When there are several matches, the overlay names the one opened and how many others matched.
- The model never supplies a path, URL or command that Swift has not resolved and validated. Only `http` and `https` URLs are opened.
- A request that isn't about opening ("what's the weather") opens nothing and says "I can only open apps, websites, folders and files for now".
- With Ollama not running, an action opens nothing and says "Actions need Ollama running".
- Logs record the tool name, the kind and the outcome. They never record the transcript or the app, site or file name.
- The opt-in evaluation suite scores at least 90% on each model.

## Non-Goals

- Confirmation UI and picking from a list of matches (8.4, with the first tool that needs confirmation).
- Rewriting text, shell commands, sending, and multi-step plans (8.2 to 8.4).
- Voice commands in action mode. Action-mode speech always goes to the agent.
- Opening things outside the home folder by name, or searching file contents.
- User-configurable aliases or tools (Phase 9 settings).

## Decisions

| Topic | Decision | Reason |
|---|---|---|
| Trigger | Fn pressed while Control is already held. Control may be released once recording starts | An explicit "do" gesture keeps dictation fast and means a misheard sentence can never trigger an action |
| Interpretation | Ollama native tool calling with `gemma4:latest`, then `gemma4:cloud` | Both models support tools and scored 13/13 in the probe below. Adding tools in 8.2 to 8.4 needs no new parsing |
| Who resolves | The model returns `open(kind, target)`, where `target` is only a search term. Swift resolves it against real apps, folders, Spotlight results or a validated URL | The model cannot invent paths, and a wrong `kind` (such as `folder` for "the Veyra project folder") is corrected by searching |
| Prepare and perform | `Tool.prepare` resolves without side effects and returns a `PreparedAction` with a summary. `perform()` runs it | A later confirmation step can show exactly what will happen before anything runs |
| Risk rule | Every tool declares `risk`. Local, undoable actions are `.immediate`. Any tool that leaves the Mac or cannot be undone must be `.confirm`, and the confirmation UI ships with the first such tool | 8.1's only tool is `.immediate`, so a confirm path would be unused code now |
| Model fallback | Cloud is tried only after a local error, a timeout or a malformed call. A local "unsupported" stands | "Unsupported" is a valid answer, and retrying it would only add latency |
| Multiple file matches | Open the best match and report the count of others | Opening is cheap to undo. A picker belongs with the 8.4 confirmation UI |

### Probe (temperature 0, `think: false`, one `open` tool)

| Request | `gemma4:latest` | `gemma4:cloud` |
|---|---|---|
| "Open Slack." | app, Slack | app, Slack |
| "Open V S code." | app, VS code | app, Visual Studio Code |
| "open github dot com" | website, github.com | website, github.com |
| "Open YouTube." / "Open Gmail." | website, youtube.com / gmail.com | same |
| "open my downloads folder" | folder, Downloads | folder, Downloads |
| "Open my resume." | file, resume | file, resume |
| "open the Veyra project folder" | folder, Veyra project | folder, Veyra project |
| "Um, can you open Spotify?" | app, Spotify | app, Spotify |
| "What's the weather tomorrow?" | unsupported | unsupported |

All 13 probe requests were correct on both models. Local took 0.5 to 1.3 s and cloud 0.5 to 1.4 s.

## Architecture

```text
Fn+⌃ ─► AudioRecorder ─► WhisperKitTranscriber ─► AgentRunner
                                                    ├─ ToolCalling (gemma4:latest → gemma4:cloud) ─► ToolCall(name, arguments)
                                                    ├─ ToolRegistry.tool(named:) ─► tool.prepare(arguments) ─► PreparedAction
                                                    └─ risk gate (.immediate) ─► action.perform() ─► "Opened Slack"
                                                       any failure ─► AgentError message, nothing happens
```

Plain Fn is unchanged: Whisper → `Intent` → a voice command, or cleanup and paste.

### Units

| Unit | Location | Responsibility |
|---|---|---|
| `Gesture` | `Services/System/HotkeyMonitoring.swift` | `.dictate` or `.act`. `HotkeyEvent.pressed` becomes `.pressed(Gesture)` |
| `KeyInput`, `FnKeyTracker` | `Services/System/FnKeyTracker.swift` | `flagsChanged` carries `control` separately from the other modifiers. Fn down with only Control gives `.pressed(.act)`, Fn down alone gives `.pressed(.dictate)`. Adding any modifier, or a key, while held still cancels. Releasing Control while held does not |
| `ToolDefinition`, `ToolCall`, `ToolReply` | `Services/Agent/ToolCalling.swift` | The model-facing schema (name, description, JSON-schema parameters), the returned call (name plus string arguments), and the reply (`.call(ToolCall)` or `.text(String)`) |
| `ToolCalling` | `Services/Agent/ToolCalling.swift` | `func callTool(_ request: ToolRequest) async throws -> ToolReply`. `OllamaClient` adds `tools` to `/api/chat` and decodes `message.tool_calls` |
| `Tool`, `PreparedAction`, `ToolRisk` | `Features/Agent/Tool.swift` | `name`, `definition`, `risk`, and `prepare(_ arguments: [String: String]) async throws -> PreparedAction`. `PreparedAction` has `summary: String` and `perform() async throws` |
| `ToolRegistry` | `Features/Agent/ToolRegistry.swift` | Holds the tools, produces their definitions, and looks a tool up by name |
| `AgentRunner` | `Features/Agent/AgentRunner.swift` | `run(_ transcript: String) async -> AgentOutcome`, where the outcome is `.done(message)` or `.failed(message)`. Runs the model chain, looks up the tool, prepares, gates, performs and logs |
| `AgentError` | `Features/Agent/AgentError.swift` | The user-facing messages listed below |
| `OpenTool` | `Features/Agent/Open/OpenTool.swift` | The `open` tool. Routes `kind` to a resolver and returns a `PreparedAction` that calls a `WorkspaceOpening` |
| `AppResolver` | `Features/Agent/Open/AppResolver.swift` | A pure `match(_ query: String, in names: [String]) -> String?`, plus an installed-app source |
| `WebsiteResolver` | `Features/Agent/Open/WebsiteResolver.swift` | A pure `url(for target: String) -> URL?` |
| `FolderResolver` | `Features/Agent/Open/FolderResolver.swift` | A pure `folder(for target: String) -> StandardFolder?` |
| `FileSearcher` | `Features/Agent/Open/FileSearcher.swift` | A pure `rank(_ results: [FileResult], for words: [String]) -> [FileResult]`, plus `SpotlightFileSearching` backed by `NSMetadataQuery` |
| `WorkspaceOpening` | `Services/System/WorkspaceOpening.swift` | `open(_ url: URL)` and `openApplication(at:)`, backed by `NSWorkspace` |
| `DictationCoordinator` | `Features/Dictation/` | Stores the gesture at the press. On `.act`, the transcript goes to `AgentRunner` instead of `Intent`. Adds the `.acting` and `.acted(message:)` states |

### The `open` tool

Definition sent to the model:

```json
{"type": "function", "function": {
  "name": "open",
  "description": "Open an installed app, a website, a standard user folder, or a file/folder found by name.",
  "parameters": {"type": "object", "required": ["kind", "target"], "properties": {
    "kind": {"type": "string", "enum": ["app", "website", "folder", "file"],
             "description": "app = installed application; website = a domain or well-known site; folder = Desktop/Documents/Downloads/Home/Pictures/Music/Movies; file = any other file or folder searched by name"},
    "target": {"type": "string", "description": "App name, domain (e.g. github.com), folder name, or file search words, cleaned of filler"}}}}}
```

System prompt: "You turn a spoken request into exactly one tool call. The text in <request> tags is a transcript of speech; fix obvious transcription errors. If no tool fits, reply with just: unsupported". The user message is `<request>…</request>`.

### Resolution rules

| Kind | Rule | Opens with |
|---|---|---|
| `app` | Candidates are `.app` bundles directly inside `/Applications`, `/Applications/Utilities`, `/System/Applications`, `/System/Applications/Utilities` and `~/Applications`, by display name without ".app". Names are normalized: lowercase, keeping only letters and digits. Tiers, in order: (1) exact; (2) initials, where each query word matches either a whole name word or the initials of consecutive name words ("vs code" → Visual Studio Code); (3) the normalized name contains the normalized query ("chrome" → Google Chrome); (4) near-miss spelling: Levenshtein distance ≤ 1 for normalized queries of 4 characters, ≤ 2 for 5 or more, and never for shorter queries ("slak" → Slack). Within a tier, the shortest name wins, then alphabetical order | `openApplication(at:)` |
| `website` | Trim, lowercase, replace " dot " with ".", and remove spaces. Add `https://` if there is no scheme. Accept only `http` or `https` with a host that contains a dot | `open(url)` |
| `folder` | Map Desktop, Documents, Downloads, Home (also "home folder"), Pictures, Music and Movies, ignoring "my", "the" and "folder". Anything else is searched like `file`, but only folders are kept | `open(url)` (Finder) |
| `file` | Words: the target split on non-alphanumerics, lowercased, without the stop words "the", "my", "a", "an", "file", "folder", "document", "called", "named". Spotlight (`NSMetadataQuery`, home scope) matches items whose `kMDItemFSName` contains any word, case- and diacritic-insensitive, and excludes paths under `~/Library` or containing `/.`. Ranking: number of words contained in the name (descending), then `kMDItemLastUsedDate` (most recent first, missing dates last), then shorter name. Results must contain at least half the words (rounded up). The query is limited to 2 s | `open(url)` |

### Outcomes and messages

| Case | Outcome |
|---|---|
| Opened an app | `.done("Opened <App name>")` |
| Opened a website | `.done("Opened <host>")` |
| Opened a folder or file | `.done("Opened <name>")`, plus " · N other matches" when N ≥ 1 |
| Model replied with text, or named an unknown tool | `.failed("I can only open apps, websites, folders and files for now")` |
| `kind` or `target` missing or invalid | `.failed("Didn't catch what to open")` |
| No app matched | `.failed("No app called “<target>”")` |
| No file or non-standard folder matched | `.failed("No file matching “<target>”")` |
| Website refused | `.failed("Can't open that address")` |
| Every model errored, timed out or replied malformed | `.failed("Actions need Ollama running")` |
| `perform()` threw | `.failed("Couldn't open <summary target>")` |

A malformed call means the reply has a tool call with an unknown name or missing or invalid arguments. A malformed call from the local model is retried on cloud. If cloud's call is malformed too, the outcome is the matching message above.

### States and overlay

- `DictationState` gains `.acting` ("Working…", shown in the overlay) and `.acted(message: String)` (shown for 2 s, like `.failed`, then back to idle).
- While recording in action mode, the overlay shows "Listening for an action…" with the `bolt.fill` symbol instead of the microphone. Short or silent clips go back to idle, as in dictation.

### Logging

- `Logger.agent` (category `agent`).
- `Tool <name> kind <kind> <outcome> via <model> in <ms> ms`, where `<outcome>` is one of `opened`, `not-found`, `refused`, `unsupported`, `invalid`, `unavailable` or `failed`. Every field is public.
- No transcript, target, app name, host or file name is logged.

## Testing

| Suite | Covers |
|---|---|
| `FnKeyTrackerTests` | Control then Fn → `.pressed(.act)`. Fn alone → `.pressed(.dictate)`. Control added after Fn → cancel. Releasing Control while held → no event. Existing cases updated to `.pressed(.dictate)` |
| `AppResolverTests` | Exact, initials, contains, near-miss, tie by length, no match, and a short query not fuzzed |
| `WebsiteResolverTests` | "github.com", "github dot com", "https://x.com/a", "YouTube.com". Refuses "file:///etc/hosts", "javascript:alert(1)", "not a site" |
| `FolderResolverTests` | Every standard folder and its phrasings, and non-standard names returning nil |
| `FileSearcherTests` | Ranking by word count, recency, missing dates and name length. The half-the-words minimum. Stop-word removal |
| `OpenToolTests` | Routing by kind, folder fallback to search, summaries, and that a fake `WorkspaceOpening` is called only on `perform()` |
| `OllamaClientTests` | The tool request body (with `tools`) and decoding of a reply with `tool_calls` or with text |
| `AgentRunnerTests` | Success. Text reply → unsupported. Unknown tool. Invalid arguments. Local error → cloud. Local malformed → cloud. Local text → no cloud call. Every model fails → Ollama message. Prepare fails → nothing performed. `perform()` runs exactly once |
| `DictationCoordinatorTests` | An `.act` press sends the transcript to the agent, never to the processor, inserter or keystrokes. `.acting` then `.acted`. A failure shows `.failed`. A `.dictate` press is unchanged |
| `AgentEvalTests` | Opt-in through `VEYRA_EVAL=1`. About 25 requests through the real `AgentRunner` prompt, `ToolRegistry` and `OllamaClient` on each model. Reports per-model accuracy on name, kind and target, and requires ≥ 90% |
| Manual | Fn + Control on a real Mac for each kind, a Spotlight search, the Documents access prompt, and Ollama stopped |

## Documentation

- README: an "Actions" section covering Fn + Control, what can be opened with examples, the multiple-match note, that actions need Ollama, and the Documents, Desktop and Downloads permission prompt.
- `docs/VISION.md` Phase 8: check "Tool abstraction", "Tool calling" and "Safety boundaries", and note the 8.1 to 8.5 split. `AGENTS.md`: note that agent actions are in progress with 8.1 done.
