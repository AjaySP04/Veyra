# Shell Commands from Speech — Design

**Date:** 2026-10-02
**Status:** Approved in conversation
**Sub-project:** 8.3 of the Veyra roadmap (Phase 8 — Agent System). Builds on 8.1 and 8.2.

## Goal

With a terminal in front, hold **Fn + Control** and describe a command — "show the five biggest files in Downloads", "git status", "how much disk space is free" — and Veyra writes the command at the prompt for you to check. **It never presses Return.**

## Success Criteria

- In Terminal, iTerm2, Ghostty, kitty, Alacritty, WezTerm, Hyper and Rio, a spoken request replaces the prompt line with one command and leaves the cursor after it. Nothing runs.
- Outside a terminal, nothing is typed and Veyra says "Open a terminal first".
- A command the model returns with a newline, carriage return or control character is never written; Veyra says "Couldn't write that as one command".
- A risky command is still written, and the overlay says "Check carefully: <reason>".
- "scratch that" afterwards removes the command; "make it recursive" rewrites it on one line.
- "open Slack" and "make this more formal" are still routed to `open` and `rewrite`.
- Logs never contain the command or the request.

## Non-Goals

- Running commands, reading their output or chaining several commands (8.4).
- Knowing the shell's current folder.
- Terminal panels inside code editors.
- Blocking risky commands.

## Decisions

| Topic | Decision | Reason |
|---|---|---|
| Where | Terminal mode only | Code editors can't tell the terminal panel from source code |
| Generation | One tool call: `shell(command:)` written by the routing model | Fastest; commands are short |
| Risky commands | Write it and warn | You stay in control, and the warning asks for a second look |
| Existing prompt text | ⌃E ⌃U clears the line first | The command can't merge with half-typed text; most shells bring it back with ⌃Y |
| Insert | The clipboard-safe paste, never Return | Matches dictation |
| Risk level | `.immediate` | Nothing runs until you press Return |
| Chaining | The command becomes the last insertion | "scratch that" and rewrite work on it |

## Units

| Unit | Location | Responsibility |
|---|---|---|
| `ShellCommand` | `Features/Agent/Shell/ShellCommand.swift` | `clean(_:) throws -> String`: trims, strips a ``` fence, surrounding backticks and a leading `$ ` or `% ` prompt. Empty → `invalidArguments`. Any newline, control character or more than 1,000 characters → `badCommand`. `ShellRisk.of(_:) -> ShellRisk?` returns the most serious match |
| `ShellRisk` | same file | `disk`, `download`, `delete`, `git`, `permissions`, `processes`, `admin`, in that order, each with a reason. `admin` (`sudo`) is last so a more specific reason wins |
| `ShellTool` | `Features/Agent/Shell/ShellTool.swift` | The `shell` tool. Refuses outside terminal mode, checks the frontmost app before and after, checks `isUntouched`, sends ⌃E ⌃U, pastes, returns the command as the insertion |

### Tool definition

- name `shell`; description "Write a shell command into the user's terminal for them to check and run. Use for command-line tasks such as listing, finding, moving or deleting files, git, disk space and processes."
- parameter `command`: "One zsh command line for macOS (BSD tools, e.g. find, du, sed -i ''), with no explanation or prompt sign"

### Risk patterns

| Risk | Matches | Reason |
|---|---|---|
| disk | `dd … of=`, `mkfs`, `diskutil erase…/zeroDisk/secureErase/partitionDisk/reformat` | "this can erase a disk" |
| download | `curl`/`wget` piped into `sh`, `bash`, `zsh`, `fish`, `python`, `ruby`, `perl`; `sh <(curl …)` | "this runs downloaded code" |
| delete | `rm` with `-r`, `-R`, `-f`, `--recursive` or `--force`; `find … -delete`; `shred`; `srm` | "this deletes files" |
| git | `git push` with `--force`/`-f`; `git reset --hard`; `git clean -f`; `git branch -D` | "this can discard git work" |
| permissions | `chmod`, `chown` or `chgrp` with `-R` | "this changes many permissions" |
| processes | `kill -9`/`-KILL`; `killall`; `pkill` | "this stops processes" |
| admin | `sudo` | "this runs as administrator" |

### Messages

| Case | Message |
|---|---|
| Written | "Command ready. Check it, then press Return" |
| Written, risky | "Check carefully: <reason>" |
| Not a terminal | "Open a terminal first" |
| Newline, control character or too long | "Couldn't write that as one command" |
| Empty | "Didn't catch what to do" |
| Paste threw | "Couldn't write the command" |
| Unsupported request | "I can open things, rewrite text and write commands for now" |

### Logging

`Shell command <n> characters, risk <category|none>`, plus the runner's line.

## Testing

| Suite | Covers |
|---|---|
| `ShellCommandTests` | Cleaning (fence, backticks, prompt sign, whitespace). Rejects newline, CR, tab, other control characters, Unicode line separators, over 1,000 characters, empty. Each risk pattern, safe look-alikes (`git add`, `rm file`, `kill 123`, `git push`), and severity order |
| `ShellToolTests` | Definition. Not terminal → `notTerminal`, nothing sent. App changed before or after → `appChanged`. Typed → `interrupted`. Perform sends ⌃E ⌃U then pastes, never Return. Messages. Insertion. Nothing happens before `perform()` |
| `AgentRunnerTests` | Updated unsupported message |
| `AgentEvalTests` | Shell routing cases; existing open and rewrite cases still pass |

## Known Limitations

- Warp's input editor may ignore ⌃U, so the command is added to what's already there.
- Relative paths are relative to wherever the shell is.

## Review Amendments

- A rewrite in a terminal gets the shell checks: wrapping is stripped, anything with a control character is refused, and a risky result says "Check carefully: <reason>".
- A command Veyra wrote owns its prompt line (`LastInsertion.ownsLine`). "scratch that" and a rewrite remove it with ⌃E ⌃U instead of one ⌫ per character, because shells such as oh-my-zsh lengthen a pasted URL.
- Risk patterns also cover `bash -c "$(curl …)"`, `curl … | /bin/bash`, `eval`/`source`/`.` of a download, and `rm` with a `*`.
