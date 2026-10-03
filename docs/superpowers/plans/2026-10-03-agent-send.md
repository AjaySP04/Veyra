# Confirmed Send Implementation Plan

> **For agentic workers:** executed natively (superpowers:executing-plans), test-first.

**Goal:** Fn + Control in chat or email writes a spoken message into the compose box; plain Fn + "send it" sends it.

**Architecture:** `ToolRisk.confirm` and a `Confirmation` step on `PreparedAction`. `AgentRunner` performs the draft and returns `.awaiting`. `DictationCoordinator` holds the pending confirmation and runs it on "send it".

**Tech Stack:** Swift 5 mode, MainActor default isolation, Swift Testing, existing fakes.

**Spec:** `docs/superpowers/specs/2026-10-03-agent-send-design.md`

## Global Constraints

- No send key outside a terminal except by confirming a pending send.
- Logs never contain the message or the request.
- Messages exactly as in the spec's Messages table.
- Test command: `xcodebuild test -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS'` (`-only-testing:VeyraTests/<Suite>` for one suite).

## Review Focus

- Typing after the draft and then "send it" must send nothing.
- Switching apps between the draft and "send it" must send nothing.
- A plain dictation between the draft and "send it" cancels the send.
- The 60 s timeout must not hide a newer state (recording, another message).
- "send it" with nothing pending presses no key.

---

### Task 1: Confirm risk in the agent

**Files:** `Features/Agent/Tool.swift`, `Features/Agent/AgentRunner.swift`, `Features/Agent/AgentError.swift` (`notMessaging`, `messageTooLong`, new `unsupported`); tests `AgentRunnerTests`, `Fakes.swift` (`FakeTool` risk and confirmation), message updates.

**Produces:** `ToolRisk.confirm`; `struct Confirmation: Equatable { done, failure, perform }`; `PreparedAction.confirmation: Confirmation?`; `AgentOutcome.awaiting(String, insertion: LastInsertion?, confirmation: Confirmation)`.

- [ ] Tests: awaiting after perform, missing confirmation refused, failing draft → `.failed`. Run → fail. Implement → pass. Commit.

### Task 2: SendKey and SendTool

**Files:** Create `Features/Agent/Send/SendKey.swift`, `Features/Agent/Send/SendTool.swift`; `Services/System/KeyChord.swift` (`commandReturn`, `sendMail`); tests `SendKeyTests`, `SendToolTests`.

**Produces:** `SendKey.for(mode:bundleIdentifier:) -> KeyChord?`; `SendTool(inserter:keystrokes:frontmostApp:)`.

- [ ] Tests first; run → fail; implement → pass. Commit.

### Task 3: Voice commands and coordinator

**Files:** `VoiceCommand.swift`, `CommandPlan.swift`, `DictationState.swift`, `DictationState+Presentation.swift`, `RecordingOverlay.swift`, `DictationCoordinator.swift` (`confirmationTimeout` init parameter); tests `CommandPlanTests`, `IntentTests`, `DictationStatePresentationTests`, `DictationCoordinatorTests`.

- [ ] Tests for each flow in the spec's Testing section; run → fail; implement → pass. Commit.

### Task 4: Wiring, evaluation and docs

**Files:** `App/AppDependencies.swift`, `AgentEvalTests.swift`, `README.md`, `docs/VISION.md`, `AGENTS.md`.

- [ ] Register; eval cases `.send(fragment)`; docs; full suite; eval. Commit.
