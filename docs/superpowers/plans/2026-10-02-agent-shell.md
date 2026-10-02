# Shell Commands Implementation Plan

> **For agentic workers:** executed natively (superpowers:executing-plans), test-first.

**Goal:** Fn + Control in a terminal writes one spoken shell command at the prompt, never pressing Return.

**Architecture:** A new `shell` tool in the existing `ToolRegistry`. `ShellCommand` cleans and validates the model's argument and classifies risk; `ShellTool` clears the prompt line (⌃E ⌃U) and pastes.

**Tech Stack:** Swift 5 mode, MainActor default isolation, Swift Testing, existing fakes.

**Spec:** `docs/superpowers/specs/2026-10-02-agent-shell-design.md`

## Global Constraints

- Never send Return. Never write a command containing a newline, carriage return, Unicode line separator or control character.
- Logs never contain the command or the request.
- Messages exactly as in the spec's Messages table.
- Test command: `xcodebuild test -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS'` (`-only-testing:VeyraTests/<Suite>` for one suite).

## Review Focus

- A model reply with a trailing newline must still work (trimmed), but an interior one must be refused.
- `git add`, `rm notes.txt`, `kill 123`, `git push` must not warn.
- `sudo rm -rf /` must say "deletes files", the more specific reason.
- Switching apps between speaking and the paste must write nothing.
- "scratch that" after a command deletes exactly the command.

---

### Task 1: ShellCommand cleaning, validation and risk

**Files:** Create `Features/Agent/Shell/ShellCommand.swift`; modify `Features/Agent/AgentError.swift` (`notTerminal`, `badCommand`, new `unsupported` message); test `VeyraTests/ShellCommandTests.swift`; update `VeyraTests/AgentRunnerTests.swift` unsupported message.

**Produces:** `enum ShellCommand { static let limit = 1_000; static func clean(_ raw: String) throws -> String }`, `enum ShellRisk: String, CaseIterable { case disk, download, delete, admin, git, permissions, processes; var reason: String; static func of(_ command: String) -> ShellRisk? }`, `AgentError.notTerminal` ("Open a terminal first"), `AgentError.badCommand` ("Couldn't write that as one command").

- [ ] Write `ShellCommandTests` (cleaning, rejections, each risk, look-alikes, severity order); run → fails to compile.
- [ ] Implement; run suite → pass. Commit.

### Task 2: ShellTool

**Files:** Create `Features/Agent/Shell/ShellTool.swift`; test `VeyraTests/ShellToolTests.swift`.

**Consumes:** Task 1. `TextInserting`, `KeystrokeSending`, `KeyChord.shellLineEnd`, `KeyChord.shellDeleteLine`.
**Produces:** `ShellTool(inserter:keystrokes:frontmostApp:)`.

- [ ] Write `ShellToolTests` (definition, not terminal, app changed before/after, interrupted, keys then paste, messages, insertion, nothing before perform); run → fails.
- [ ] Implement; run → pass. Commit.

### Task 3: Wiring, evaluation and docs

**Files:** `App/AppDependencies.swift` (register `ShellTool`), `VeyraTests/AgentEvalTests.swift` (shell cases), `README.md`, `docs/VISION.md`, `AGENTS.md`.

- [ ] Register the tool; add eval cases `.shell(fragment)`; document; full suite → pass; run eval. Commit.
