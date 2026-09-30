
# Veyra

**Veyra is a local-first AI voice interface for macOS.**

The long-term goal is to build a fast, private, extensible voice agent that lets users control their computer through natural speech — starting with high-quality local dictation and gradually evolving into an intelligent computer interaction layer.

Veyra is also being built as a learning project to understand the complete AI systems stack from the ground up: audio processing, speech recognition, local LLM inference, context engineering, tool calling, agent orchestration, observability, and system integration.

---

## Mission

Build a **local-first AI voice agent for macOS** that can:

- Convert speech to text locally.
- Provide unlimited offline dictation.
- Understand the context of the active application.
- Improve and format dictated text using a local LLM.
- Support voice commands and text manipulation.
- Interact with macOS applications.
- Eventually execute actions through tools and agents.
- Keep user data private by default.

The project will prioritize:

> **Local inference → low latency → privacy → extensibility → intelligent interaction**

---

## Product Vision

Veyra starts as a dictation tool:

```text
Voice
  ↓
Speech Recognition
  ↓
Text
  ↓
Active Application
```

It will gradually evolve into:

```text
                         Veyra
                           │
                    Voice Interface
                           │
             ┌─────────────┴─────────────┐
             │                           │
          Dictation                   Intent
             │                           │
             ▼                 ┌─────────┼─────────┐
        Text Processing         │         │         │
                              Dictate   Command   Action
                                         │         │
                                         ▼         ▼
                                      Context    Tools
                                                   │
                                                   ▼
                                                 Agent
```

The ultimate goal is not simply speech-to-text.

**The goal is a voice-native interface for interacting with a computer.**

---

# Core Principles

### Local First

Veyra should prefer local inference whenever practical.

```text
Microphone
    ↓
Local Speech Model
    ↓
Local LLM
    ↓
Local Application
```

Cloud APIs may eventually be supported as optional providers, but they should not be required for the core dictation experience.

### Privacy

Audio and transcripts should remain on the user's machine by default.

### Modular

Major AI capabilities should be replaceable.

For example:

```text
TranscriptionService
       │
       ├── WhisperKit
       ├── whisper.cpp
       └── Cloud Provider
```

Similarly:

```text
LLMService
    │
    ├── Ollama
    ├── Local Model
    └── Cloud Provider
```

### Understandable Systems

Veyra is intentionally being built incrementally.

Every major subsystem should be understood before it is abstracted.

---

# Technology Stack

## Application

### Swift

Primary programming language.

Used for:

- macOS application development
- concurrency
- application services
- system integration
- AI inference integration

### SwiftUI

Used for the user interface.

Initial UI:

```text
Veyra
 ├── Recording state
 ├── Start / Stop
 └── Settings
```

The UI will eventually evolve into a lightweight menu-bar application.

### AppKit

Used alongside SwiftUI for macOS-specific functionality such as:

- active application detection
- clipboard interaction
- accessibility APIs
- text injection
- window/application integration
- menu-bar behavior

---

# Audio Stack

## AVFoundation

Veyra uses Apple's native audio framework for microphone capture.

Current pipeline:

```text
Microphone
    ↓
AVAudioEngine
    ↓
AVAudioInputNode
    ↓
Audio Tap
    ↓
AVAudioPCMBuffer
```

Eventually:

```text
AVAudioPCMBuffer
    ↓
Audio Processing
    ↓
16 kHz Mono PCM
    ↓
Speech Recognition
```

---

# Speech Recognition

## WhisperKit

WhisperKit will provide local Whisper-based speech recognition on Apple Silicon.

Planned pipeline:

```text
Microphone
    ↓
AVAudioEngine
    ↓
PCM Audio
    ↓
WhisperKit
    ↓
Transcript
```

The initial implementation will use WhisperKit because it provides a native Swift/Core ML path for local inference on Apple hardware.

Alternative implementations such as `whisper.cpp` may be explored later for comparison and learning.

---

# Local LLM

## Ollama

Ollama will provide the local LLM runtime for higher-level language processing.

Example:

```text
Raw Transcript

"hey team uh basically payment integration
is done and testing is left"

        ↓

Ollama

"Hey team,

The payment integration is complete,
and testing is the remaining task."
```

Potential uses:

- grammar correction
- punctuation
- formatting
- rewriting
- summarization
- application-specific formatting
- intent classification
- command interpretation

---

# Local Models

The exact model will evolve as the project develops.

Potential models include:

- Qwen
- Gemma
- Llama
- other efficient local instruction-tuned models

Model selection will be evaluated based on:

- latency
- memory usage
- quality
- context length
- structured output reliability
- Apple Silicon performance

---

# macOS Integration

Veyra will eventually integrate deeply with macOS.

Planned capabilities:

```text
Global Hotkey
     ↓
Start / Stop Dictation
     ↓
Transcribe
     ↓
Process
     ↓
Insert into Active Application
```

Potential integrations:

- Clipboard
- Accessibility API
- Global keyboard shortcuts
- Active application detection
- Menu bar
- Notifications
- System permissions

---

# Architecture

Veyra will use a modular service-oriented architecture.

Current direction:

```text
Veyra
│
├── App
│
├── Features
│   ├── Dictation
│   └── Settings
│
├── Services
│   ├── Audio
│   ├── Speech
│   ├── AI
│   ├── System
│   └── Storage
│
├── Models
│
└── Core
```

Example service boundaries:

```text
AudioRecorder
       ↓
TranscriptionService
       ↓
TextProcessor
       ↓
TextInjectionService
```

Later:

```text
Voice Input
     ↓
Audio Service
     ↓
Speech Service
     ↓
Context Engine
     ↓
Intent Router
     ↓
┌──────────────┬──────────────┬──────────────┐
│  Dictation   │   Command    │    Agent     │
└──────────────┴──────────────┴──────────────┘
```

---

# Development Principles

## Small Incremental Milestones

The project is intentionally developed in small stages.

Example:

```text
1. Capture microphone audio
2. Save audio
3. Play audio
4. Transcribe audio
5. Improve transcription
6. Add global hotkey
7. Inject text
8. Add local LLM
9. Add application context
10. Add voice commands
11. Add tools
12. Add agent orchestration
```

Each stage should produce something usable.

---

# Testing

Veyra uses Swift's testing infrastructure.

Tests will eventually cover:

```text
Audio
Speech
Text Processing
Intent Detection
Commands
AI Services
System Integration
```

The goal is to keep core logic testable independently from:

- microphone hardware
- macOS UI
- external applications
- AI model execution

---

# Performance Goals

Veyra is intended to feel like a native computer interaction tool.

Important metrics:

### Speech latency

```text
Speech ends
     ↓
Transcript available
```

### Processing latency

```text
Transcript
     ↓
LLM
     ↓
Formatted result
```

### End-to-end latency

```text
Speech
  ↓
Audio Capture
  ↓
VAD
  ↓
Whisper
  ↓
LLM
  ↓
Text Injection
```

Performance will be measured rather than assumed.

---

# Privacy Model

Default behavior should be:

```text
                    User Device
┌─────────────────────────────────────────┐
│                                         │
│  Microphone                             │
│      ↓                                  │
│  WhisperKit                             │
│      ↓                                  │
│  Ollama                                 │
│      ↓                                  │
│  Veyra                                  │
│      ↓                                  │
│  Active Application                     │
│                                         │
└─────────────────────────────────────────┘

              No cloud required
```

Cloud-based providers may eventually be supported as explicit user-selected alternatives.

---

# Roadmap

## Phase 0 — Foundation

- [x] Create macOS application
- [x] Configure SwiftUI
- [x] Configure unit tests
- [x] Establish project structure
- [x] Verify Apple Silicon build

## Phase 1 — Audio

- [x] Initialize AVAudioEngine
- [x] Access microphone input
- [x] Receive PCM buffers
- [x] Start/stop recording
- [ ] Save recordings
- [ ] Verify recorded audio
- [ ] Playback recorded audio
- [ ] Understand audio formats
- [ ] Resample to Whisper-compatible format

## Phase 2 — Speech Recognition

- [ ] Integrate WhisperKit
- [ ] Download/load local Whisper model
- [ ] Transcribe recorded audio
- [ ] Measure transcription latency
- [ ] Compare Whisper model sizes
- [ ] Evaluate transcription quality

## Phase 3 — Real-Time Dictation

- [ ] Voice Activity Detection
- [ ] Streaming audio
- [ ] Incremental transcription
- [ ] Partial results
- [ ] Latency optimization

## Phase 4 — macOS Dictation

- [ ] Global keyboard shortcut
- [ ] Menu-bar application
- [ ] Accessibility permissions
- [ ] Active application detection
- [ ] Clipboard integration
- [ ] Text injection

## Phase 5 — Local AI Processing

- [ ] Integrate Ollama
- [ ] Select local LLM
- [ ] Transcript cleanup
- [ ] Grammar correction
- [ ] Formatting
- [ ] Structured outputs
- [ ] Prompt management

## Phase 6 — Context Engineering

- [ ] Detect active application
- [ ] Application-specific prompts
- [ ] Developer mode
- [ ] Email mode
- [ ] Chat mode
- [ ] Terminal mode
- [ ] Context management

## Phase 7 — Voice Commands

- [ ] Intent classification
- [ ] Text editing commands
- [ ] Formatting commands
- [ ] Undo/redo
- [ ] Command routing

## Phase 8 — Agent System

- [ ] Tool abstraction
- [ ] Tool calling
- [ ] Agent state
- [ ] Planning
- [ ] Execution
- [ ] Safety boundaries
- [ ] Agent evaluation

## Phase 9 — Production

- [ ] Performance optimization
- [ ] Crash reporting
- [ ] Observability
- [ ] Model management
- [ ] Settings
- [ ] Auto-update
- [ ] Code signing
- [ ] Notarization
- [ ] Distribution

---

# Learning Objectives

Veyra is also an AI Systems Engineering project.

The project is designed to develop practical understanding of:

- Audio processing
- Speech recognition
- Transformer inference
- Local LLMs
- Model selection
- Prompt engineering
- Context engineering
- Structured generation
- Tool calling
- Agent orchestration
- Memory
- Evaluation
- Observability
- Latency optimization
- Token/cost optimization
- Concurrency
- OS integration
- Privacy-preserving AI
- Production AI systems

---

# Current Status

**Stage:** Phase 1 — Audio Capture

Current working pipeline:

```text
🎙️ Microphone
      ↓
AVAudioEngine
      ↓
AVAudioInputNode
      ↓
Audio Tap
      ↓
AVAudioPCMBuffer
      ↓
Console
```

Next milestone:

```text
AVAudioPCMBuffer
      ↓
AVAudioFile
      ↓
recording.wav
      ↓
Playback verification
```

---

# Using Veyra

1. Build and run the `Veyra` scheme. A microphone icon appears in the menu bar.
2. Grant **Microphone** and **Accessibility** access when prompted (or from the menu).
3. Set **System Settings → Keyboard → Press 🌐 key to → Do Nothing** so Fn doesn't open the emoji picker.
4. The first launch downloads the Whisper `large-v3-turbo` model (~1.6 GB) into `~/Library/Application Support/Veyra/Models`. After that Veyra works offline.
5. Hold **Fn**, speak, release. The text is pasted where your cursor is.

If dictation stops working after a rebuild, remove Veyra from **Privacy & Security → Accessibility** and add it again.

---

# Development Philosophy

Veyra is intentionally built slowly.

The goal is not:

> "Build an AI app as quickly as possible."

The goal is:

> **Understand every layer well enough to design, debug, replace, and scale it.**

The project should eventually become both a useful product and a practical demonstration of AI Systems Engineering.

---

## Initial Technology Stack

```text
Language:              Swift
UI:                    SwiftUI
macOS APIs:            AppKit
Audio:                 AVFoundation
Speech:                WhisperKit
Local LLM Runtime:     Ollama
LLMs:                  Qwen / Gemma / Llama
Testing:               Swift Testing
Build:                 Xcode
Dependency Management: Swift Package Manager
Version Control:       Git
Platform:              macOS / Apple Silicon
```

---

## Project Name

**Veyra**

A local-first AI voice interface for macOS.
