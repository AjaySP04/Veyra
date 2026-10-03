# Confirmed Send — Design

**Date:** 2026-10-03
**Status:** Approved in conversation
**Sub-project:** 8.4a of the Veyra roadmap (Phase 8 — Agent System). Multi-step plans are 8.4b, with their own spec.

## Goal

With a chat or email open, hold **Fn + Control** and say what to send — "reply sounds good, see you at 5". Veyra writes the message into the compose box and waits. Hold plain **Fn** and say **"send it"** to send. Nothing leaves the Mac without that confirmation.

This is the first `.confirm` tool. The confirmation path it adds is the one 8.4b reuses to confirm a whole plan.

## Success Criteria

- In chat mode (Slack, Teams, WhatsApp, Messages, Discord, Telegram, chat sites) and email mode (Mail, Outlook, Spark, Gmail and Outlook on the web), a send request pastes the message at the cursor and presses nothing else. The overlay stays up with "Say “send it” to send".
- "send it", "send that", "send this" or "send" presses the app's send key once and shows "Sent".
- Typing, clicking, secure input, switching apps, "scratch that", "cancel", any other dictation, command or action, or 60 seconds without confirmation cancels the pending send. The draft stays in the box (except after "scratch that", which deletes it).
- Outside chat and email, nothing is typed and Veyra says "Open a chat or email first".
- "send it" with nothing pending says "Nothing to send" and presses nothing.
- Return, ⌘Return and ⌘⇧D are never sent outside a terminal except by confirming a pending send.
- Logs never contain the message or the request.

## Non-Goals

- Sending to a named person or opening a conversation (8.4b).
- "send it" after plain dictation. A send always needs a request and a confirmation.
- Reading the compose box, attachments, subjects or recipients.
- A clickable or keyboard confirmation UI.

## Decisions

| Topic | Decision | Reason |
|---|---|---|
| Target | The app in front, in chat or email mode | No integrations; works everywhere dictation already works |
| Draft | Pasted at the cursor, never replacing existing text | You see exactly what goes out, in the app |
| Confirmation | Plain Fn + "send it" | Same habit as "run it"; no new input capture; the overlay can stay click-through |
| Where the pending send lives | `DictationCoordinator`, next to `lastInsertion` | Typing already clears `lastInsertion`, so cancelling is shared; 8.4b reuses the slot |
| Risk | `ToolRisk.confirm`; `AgentRunner` performs the draft and returns `.awaiting` instead of `.done` | A `.confirm` tool without a confirmation step is refused |
| Timeout | 60 seconds | Long enough to reread; short enough that a forgotten send can't fire later |
| "send it" with nothing pending | "Nothing to send" | No silent Return |

## Units

| Unit | Location | Responsibility |
|---|---|---|
| `ToolRisk.confirm`, `Confirmation` | `Features/Agent/Tool.swift` | `Confirmation(done:failure:perform:)`; `PreparedAction.confirmation` |
| `AgentOutcome.awaiting` | `Features/Agent/AgentRunner.swift` | `.awaiting(prompt, insertion:, confirmation:)`. `.confirm` tools: perform the draft, then return `.awaiting`. No confirmation → `.failed(action.failure)`, nothing performed |
| `SendKey` | `Features/Agent/Send/SendKey.swift` | `for(mode:bundleIdentifier:) -> KeyChord?`: chat → Return; Mail → ⌘⇧D; other email → ⌘Return; else nil |
| `SendTool` | `Features/Agent/Send/SendTool.swift` | The `send` tool. Chat or email only; frontmost app checked before preparing, before pasting and before sending; `isUntouched` checked before pasting and before sending; message trimmed and stripped of wrapping quotes; empty → `invalidArguments`; over 4,000 characters → `messageTooLong` |
| `VoiceCommand.send`, `.cancelSend` | `Features/Commands/` | Phrases below. Their plans are "Nothing to send" / "Nothing to cancel"; the coordinator handles them when a send is pending |
| `DictationState.awaiting(message:)` | `Features/Dictation/` | Overlay with a paper-plane icon; visible until confirmed or cancelled; Fn presses allowed |
| Coordinator | `DictationCoordinator` | Holds the pending send, its app and the 60 s timer; confirms, cancels, expires |

### Tool definition

- name `send`; description "Write a message into the chat or email the user has open, for them to confirm before it is sent. Use when the user asks to reply, send, answer, tell or message someone in the open conversation and says what to write. If they don't say what the message is, don't use this tool."
- parameter `message`: "The message the user asked to send, written as the user in the first person, with no quotes or explanation. Never make one up"

### Phrases

| Command | Phrases |
|---|---|
| send | "send it", "send that", "send this", "send" |
| cancelSend | "cancel", "cancel it", "cancel that", "don't send", "do not send" |

### Messages

| When | Message |
|---|---|
| Draft written, chat | Say “send it” to send |
| Draft written, email | Say “send it” to send the email |
| Confirmed | Sent |
| Confirm failed | Couldn't send |
| Draft paste failed | Couldn't write the message |
| Not chat or email | Open a chat or email first |
| Too long | That message is too long |
| "cancel" with a pending send | Not sent |
| "send it" with nothing pending | Nothing to send |
| "cancel" with nothing pending | Nothing to cancel |
| App changed before sending | Cancelled because the app changed |
| Unsupported request | I can open things, rewrite text, write commands and send messages for now |

## Flow

1. Fn + Control, "reply sounds good". `AgentRunner` → `send(message:)`. `SendTool.prepare` checks mode, app and message. `AgentRunner` sees `.confirm`, performs the paste, returns `.awaiting`.
2. The coordinator stores the pending send with its app, sets `lastInsertion` to the draft, shows `.awaiting`, and starts a 60 s timer.
3. Plain Fn, "send it" → `Intent.command(.send)`. The coordinator takes the pending send, checks the frontmost app, shows `.acting`, runs `confirm` (which re-checks the app and `isUntouched`, then presses the send key), and shows "Sent". `lastInsertion` is cleared: a sent message can't be scratched.
4. Anything else cancels as listed in Success Criteria. A recording that is too short or silent returns to `.awaiting` while the send is still pending.

## Testing

- `SendKeyTests`: each mode and app.
- `SendToolTests`: definition, modes, app changed before preparing/pasting/sending, typing before pasting/sending, quotes stripped, empty, too long, nothing before perform, paste only, the confirm step presses exactly the send key.
- `AgentRunnerTests`: `.confirm` returns `.awaiting` after performing; missing confirmation is refused; failure to draft is `.failed`.
- `DictationCoordinatorTests`: send it, cancel, typing, app switch, timeout, other dictation, scratch that, nothing to send, short clip keeps the prompt.
- `CommandPlanTests`: "send it" plans no keys anywhere; the Phase 7 Return guarantee holds.
- Eval: send routing cases and unchanged open/rewrite/shell routing.
