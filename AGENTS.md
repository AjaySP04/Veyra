## Agent skills

### Issue tracker

Issues are tracked as GitHub Issues (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout (one `CONTEXT.md` + `docs/adr/` at the repo root). See `docs/agents/domain.md`.

## Roadmap

- [x] Local dictation with a global Fn hotkey
- [x] Transcript cleanup with Ollama (`gemma4:latest`, then `gemma4:cloud`) behind `TextProcessing`
- [x] App-aware modes (email, chat, editor, terminal)
- [ ] Voice commands and agent actions

Detailed phases, principles and the long-term vision are in `docs/VISION.md`.
