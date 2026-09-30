<p align="center">
  <img src="docs/assets/veyra-icon.png" width="128" alt="Veyra icon">
</p>

<h1 align="center">Veyra</h1>

<p align="center"><b>Private, unlimited voice dictation for macOS.</b><br>
Hold <b>Fn</b>, speak, release — your words appear wherever your cursor is.</p>

---

## Features

- **Works in any app** — Notes, Slack, VS Code, browsers, Terminal.
- **Fully local** — Whisper runs on your Mac. No account, no usage limits, works offline.
- **Noise-aware** — Apple voice processing plus optional Voice Isolation for busy rooms.
- **Clipboard-safe** — your previous clipboard is restored after every paste.

## Requirements

- Mac with Apple Silicon, macOS 26.5 or later
- Xcode 26 or later (Veyra is built from source)
- ~2 GB free disk space for the speech model

## Installation

```bash
git clone https://github.com/AjaySP04/Veyra.git
cd Veyra
./scripts/install.sh
```

This builds Veyra, installs it to `/Applications`, and launches it. A microphone icon appears in the menu bar.

> Building with your own Apple ID? Open `Veyra.xcodeproj` → **Veyra** target → **Signing & Capabilities** and pick your team first.

### First launch

1. **Allow microphone access** when prompted.
2. **Turn on Accessibility:** System Settings → Privacy & Security → Accessibility → **Veyra**.
3. **Free up the Fn key:** System Settings → Keyboard → *Press 🌐 key to* → **Do Nothing**.
4. **Wait for the model:** the first launch downloads Whisper (~1.6 GB). The menu shows progress, then **Hold Fn to dictate**.

Optional: add Veyra to **System Settings → General → Login Items** to start it automatically.

## Usage

| Action | How |
|---|---|
| Dictate | Hold **Fn**, speak, release |
| Cancel | Press any other key while holding Fn |
| Reduce background voices | Veyra menu → **Microphone Mode…** → **Voice Isolation** |
| Quit | Veyra menu → **Quit Veyra** (⌘Q) |

Veyra transcribes in English.

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing is typed | Open the Veyra menu and grant any permission it lists. |
| Fn opens the emoji picker | Set *Press 🌐 key to* → **Do Nothing**. |
| Menu shows an error | Check your connection and click **Retry**. |
| Fn stops working after an update | Remove Veyra from Accessibility, then add it again. |

View diagnostics (never includes your words):

```bash
log stream --level info --predicate 'subsystem == "com.ajaysparmar.Veyra"'
```

## Update and uninstall

```bash
# Update
git pull && ./scripts/install.sh

# Uninstall
pkill -x Veyra
rm -rf /Applications/Veyra.app "$HOME/Library/Application Support/Veyra"
defaults delete com.ajaysparmar.Veyra
tccutil reset All com.ajaysparmar.Veyra
```

## Development

```bash
open Veyra.xcodeproj                                                        # run the Veyra scheme
xcodebuild test -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS'
```

```text
Fn ─► FnKeyMonitor ─► DictationCoordinator ─► AudioRecorder ─► WhisperKitTranscriber ─► PasteboardTextInserter
```

Built with Swift, SwiftUI, AVFoundation and [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift). Each service sits behind a protocol, so engines can be swapped and the coordinator is tested with fakes.

## Roadmap

- [x] Local dictation with a global Fn hotkey
- [ ] Transcript cleanup and formatting with a local LLM (Ollama)
- [ ] App-aware modes (email, chat, code)
- [ ] Voice commands and agent actions

The full vision, principles and detailed roadmap are in [docs/VISION.md](docs/VISION.md).
