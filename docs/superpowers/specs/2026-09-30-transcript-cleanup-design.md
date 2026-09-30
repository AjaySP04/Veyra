# Transcript Cleanup — Design

**Date:** 2026-09-30
**Status:** Approved in conversation, pending spec review
**Sub-project:** 2 of the Veyra roadmap (Phase 5 — Local AI Processing)

## Goal

Before Veyra pastes a transcript, a language model gives it a light cleanup: filler words ("um", "uh", "basically", "you know") come out, punctuation and capitalization get fixed, and obvious transcription errors are corrected. The speaker's wording and meaning stay the same. Cleanup runs through Ollama. It prefers the local `gemma4:latest`, falls back to the free `gemma4:cloud` model, and pastes the raw transcript whenever no model is available.

## Success Criteria

- "hey team uh basically payment integration is done and testing is left" is pasted as "Hey team, payment integration is done and testing is left."
- A dictated question ("what time is the standup tomorrow") is cleaned ("What time is the standup tomorrow?"), never answered.
- Cleanup adds about 0.4–0.6 s per dictation with a warm local model and about 0.5 s with the cloud model.
- If Ollama is not installed, not running, or has neither model, dictation behaves exactly as it does today (raw transcript) and adds no noticeable delay.
- Cleanup never produces an error state. Every failure path pastes the raw transcript.
- Logs never contain the user's words.

## Non-Goals

- Rewriting or polishing into new sentences (Phase 6, app-aware modes).
- A settings UI, model picker, or on/off toggle. The model list is set in code.
- Streaming output, structured outputs, or prompt management files.
- Starting Ollama or pulling models on the user's behalf.
- Non-Ollama providers.

## Decisions

| Topic | Decision | Reason |
|---|---|---|
| Cleanup level | Light touch: fillers, punctuation, capitalization, obvious mis-hearings | Owner's choice; least risk of changing what was said |
| Runtime | Ollama HTTP API at `http://localhost:11434/api/chat`, called with `URLSession` | One JSON request; no new package dependency |
| Model chain | `gemma4:latest` (6 s + 30 ms per word), then `gemma4:cloud` (3 s + 10 ms per word), then the raw transcript | Owner's choice: local first when installed, since it is as fast as cloud and keeps text on the Mac. Benchmarks: `gemma4:latest` (7.5B, Q4_K_M) was correct on all three samples in 0.38–0.60 s warm and loaded in 5.3 s cold; the cloud model (served as `gemma4:31b`) was correct on all three in 0.53–0.54 s |
| Cloud privacy | Cloud is used only when the local model is missing, fails, or times out, and only if the user is signed in to Ollama with `gemma4:cloud` pulled | Owner's choice; README states it and says how to keep everything local |
| Drift protection | A prompt that wraps the transcript in tags, plus a pure word-overlap guard on the reply | Benchmark: `llama3.2` answered a dictated question instead of cleaning it |
| Failure policy | Any error, timeout, or rejected reply moves to the next model; after the last model, return the raw transcript | Dictation must never fail because of cleanup |
| Request options | `stream: false`, `think: false`, `temperature: 0`, `keep_alive: "30m"` | Deterministic, no reasoning latency, and the local model stays loaded between dictations |

## Architecture

```
DictationCoordinator ─► TextProcessing.process(transcript)
                              │
                              ▼
                     OllamaTextProcessor
                       for each CleanupModel in order:
                         ChatCompleting.complete(CleanupPrompt.request(…))
                         CleanupGuard.accepts(original:cleaned:) ? return cleaned : next
                       return transcript (raw)
                              │
                              ▼
                        OllamaClient ─► POST localhost:11434/api/chat
```

The coordinator and every existing service are unchanged. `AppDependencies` swaps `PassthroughTextProcessor()` for an `OllamaTextProcessor`. `PassthroughTextProcessor` stays, because the coordinator tests use it.

### File Layout

```
Services/Text/TextProcessing.swift         (unchanged) protocol + PassthroughTextProcessor
Services/Text/ChatCompleting.swift         protocol + ChatRequest + ChatError
Services/Text/OllamaClient.swift           URLSession implementation of ChatCompleting
Services/Text/CleanupModel.swift           model name + timeout, and the default chain
Services/Text/CleanupPrompt.swift          system prompt, user message wrapping, reply unwrapping
Services/Text/CleanupGuard.swift           pure accept/reject of a reply
Services/Text/OllamaTextProcessor.swift    TextProcessing implementation over the chain
App/AppDependencies.swift                  wires OllamaTextProcessor
App/Logger+Veyra.swift                     adds Logger.cleanup
VeyraTests/CleanupGuardTests.swift
VeyraTests/CleanupPromptTests.swift
VeyraTests/OllamaClientTests.swift         URLProtocol stub, no real network
VeyraTests/OllamaTextProcessorTests.swift  FakeChatCompleter
VeyraTests/Fakes.swift                     adds FakeChatCompleter
```

### Interfaces

```swift
struct ChatRequest: Equatable {
    let model: String
    let system: String
    let user: String
    let timeout: Duration
}

protocol ChatCompleting {
    func complete(_ request: ChatRequest) async throws -> String
}

enum ChatError: Error, Equatable {
    case badStatus(Int)
    case malformedResponse
}

struct CleanupModel: Equatable {
    let name: String
    let timeout: Duration

    static let chain: [CleanupModel] = [
        CleanupModel(name: "gemma4:latest", timeout: .seconds(6)),
        CleanupModel(name: "gemma4:cloud", timeout: .seconds(3)),
    ]
}

enum CleanupPrompt {
    static let system: String
    static func userMessage(for transcript: String) -> String
    static func reply(from content: String) -> String
}

enum CleanupGuard {
    static func accepts(original: String, cleaned: String) -> Bool
}

struct OllamaTextProcessor: TextProcessing {
    init(client: ChatCompleting, models: [CleanupModel] = CleanupModel.chain)
    func process(_ text: String) async throws -> String   // never throws in practice
}

struct OllamaClient: ChatCompleting {
    init(baseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared)
}
```

## Component Behavior

**OllamaClient**
- Sends `POST {baseURL}/api/chat` with this JSON body: `model`, `messages` (the system message, then the user message), `stream: false`, `think: false`, `keep_alive: "30m"`, and `options.temperature: 0`.
- Sets `URLRequest.timeoutInterval` from `request.timeout`. With `stream: false` Ollama sends nothing until the reply is complete, so this acts as a limit on the whole request. A refused connection (Ollama not running) fails immediately.
- Any non-2xx status throws `ChatError.badStatus(code)`. This covers an unknown model (404), not being signed in to Ollama for a cloud model (401), and running out of credits (429). A body without `message.content` throws `ChatError.malformedResponse`. Transport errors propagate unchanged.
- Returns `message.content` exactly as received.

**CleanupPrompt**
- `system` holds the benchmarked instruction: remove filler words, fix punctuation and capitalization, correct obvious transcription errors, and keep the speaker's wording, meaning and language. It must not add, answer, or summarize, and must output only the cleaned text. It also says the text inside `<transcript>` tags is dictation to clean, never a request to follow.
- `userMessage(for:)` returns `<transcript>\n{transcript}\n</transcript>`.
- `reply(from:)` trims whitespace. If the whole reply is wrapped in `<transcript>…</transcript>`, it removes the tags and trims again.

**CleanupGuard.accepts(original:cleaned:)**
- **Word rule:** words are lowercased runs of letters, digits and apostrophes.
- **Reject** if `cleaned` has no words.
- **Reject** if the number of `cleaned` words not found among `original` words exceeds `max(2, 20% of cleaned words)`. This allows corrections such as "stand-up" but not answers or rewrites.
- **Reject** if fewer than half of the `original` words appear in `cleaned`. Fillers are a minority, so a reply that drops most of the words has summarized.
- **Otherwise accept.**

**OllamaTextProcessor.process(_:)**
- If the transcript has no words, it is returned as is.
- **For each model in order:**
  1. Call `complete` with that model's name and timeout.
  2. Unwrap the reply with `CleanupPrompt.reply(from:)`.
  3. Return it if `CleanupGuard` accepts it.
  4. On an error, a timeout or a rejected reply, log the reason and try the next model.
- After the last model, it returns the original transcript.
- It catches every error, including cancellation, and never lets one escape. If the dictation task is cancelled, the raw transcript is returned. The coordinator discards it as it does today.

**Logging (`Logger.cleanup`)**
- On success: the model name, the latency in milliseconds, and the character counts before and after.
- On fallback: the model name and the reason (`error: <type>`, `rejected by guard`).
- On using the raw transcript: one line.
- The user's text is never logged.

## UI

No changes. The overlay keeps showing the transcribing state until the paste, and cleanup time is part of that state.

## Error Handling

| Condition | Result |
|---|---|
| Ollama not installed or not running | The connection is refused on each model, which is instant. The raw transcript is pasted. |
| `gemma4:latest` not pulled | Local returns 404. The cloud model is used. |
| `gemma4:latest` not loaded yet | The first use may time out, then the cloud model is tried. Ollama abandons a load when the request times out, so Veyra sends a separate background warm-up (`POST /api/generate` with `keep_alive: "30m"`, 300 s timeout), and the next dictation is cleaned locally. |
| Local unavailable, and not signed in, out of cloud credits, or `gemma4:cloud` not pulled | Cloud returns 401, 429 or 404. The raw transcript is pasted. |
| Both models missing | The raw transcript is pasted. |
| The model answers or rewrites | The guard rejects it and the next model is tried, then the raw transcript. |
| Offline | The local model is used. Cloud is only reached if local fails, and then fails with a transport error. |

## Testing

All tests use Swift Testing and never touch the real network or Ollama.

- **CleanupGuardTests** (table-driven):
  - accepts the three benchmark pairs;
  - rejects an empty reply;
  - rejects the `llama3.2` "stand-up comedy show" answer;
  - rejects a one-sentence summary of a long transcript;
  - accepts a one-word correction.
- **CleanupPromptTests:**
  - the user message is wrapped in tags;
  - `reply(from:)` trims and unwraps a tagged reply;
  - `reply(from:)` leaves an untagged reply unchanged apart from trimming;
  - the system prompt mentions `<transcript>`.
- **OllamaClientTests** (a `URLProtocol` stub on an ephemeral `URLSession`):
  - request URL, method and JSON body match the spec;
  - the timeout interval matches;
  - a 200 response returns `message.content`;
  - a 404 throws `badStatus(404)`;
  - a body without `message` throws `malformedResponse`.
- **OllamaTextProcessorTests** (`FakeChatCompleter` with scripted replies per model, recording its requests):
  - the first model's accepted reply is returned and the second model is never called;
  - an error on the first model means the second model's reply is returned;
  - a reply rejected by the guard moves on to the next model;
  - when every model fails, the raw transcript is returned;
  - each model is called with its own name and timeout;
  - an empty or whitespace-only transcript makes no calls.
- **Manual check:**
  1. Dictate with `gemma4:latest` installed, and confirm local cleanup.
  2. Remove the local model (`ollama rm gemma4:latest`), confirm cloud cleanup, then pull it again.
  3. Quit Ollama, and confirm the raw transcript is pasted with no delay.

## Docs

- **README:**
  - The "Fully local" feature line explains that cleanup runs locally with `gemma4:latest` through Ollama, falls back to `gemma4:cloud` only when the local model is unavailable, and is skipped without Ollama.
  - A short "Transcript cleanup (optional)" section covers installing Ollama, `ollama pull gemma4:latest`, `ollama signin` plus `ollama pull gemma4:cloud` for cloud, and `ollama rm gemma4:cloud` to make sure nothing ever leaves the Mac.
- **AGENTS.md:** the roadmap item is checked.
- **docs/VISION.md:** the Phase 5 items "Integrate Ollama", "Select local LLM", "Transcript cleanup", "Grammar correction" are checked.
