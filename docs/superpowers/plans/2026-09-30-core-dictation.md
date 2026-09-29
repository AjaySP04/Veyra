# Core Dictation Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hold Fn anywhere on macOS, speak, release, and the locally transcribed text is pasted at the cursor.

**Architecture:** Small single-purpose services behind protocols (`AudioCapturing`, `Transcribing`, `TextProcessing`, `TextInserting`, `HotkeyMonitoring`, `PermissionChecking`) are composed in `AppDependencies` and driven by one `@Observable` `DictationCoordinator` state machine. SwiftUI renders a `MenuBarExtra` and a floating non-activating overlay from the coordinator's `state`.

**Tech Stack:** Swift 5 language mode (Xcode 27 toolchain, default `MainActor` isolation, approachable concurrency), SwiftUI + AppKit, AVFoundation/Accelerate, WhisperKit from `argmax-oss-swift` 1.1.0, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-30-core-dictation-design.md`

## Global Constraints

- macOS deployment target 26.5, Apple Silicon; bundle id `com.ajaysparmar.Veyra`.
- WhisperKit package `https://github.com/argmaxinc/argmax-oss-swift`, `upToNextMajorVersion` from `1.1.0`, product `WhisperKit`.
- Model variant `large-v3-v20240930_turbo`, stored under `~/Library/Application Support/Veyra/Models`.
- `ENABLE_APP_SANDBOX = NO`, `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES` (hardened runtime mic entitlement), `INFOPLIST_KEY_LSUIElement = YES`.
- `INFOPLIST_KEY_NSMicrophoneUsageDescription = "Veyra listens while you hold Fn to transcribe your speech."`
- Audio handed to the transcriber is 16 kHz mono Float32 (`AudioFormat.sampleRate`).
- Clips shorter than 0.3 s or quieter than normalized level 0.1 are not transcribed.
- Clipboard restore delay 250 ms; transient failure display 2 s.
- Code style: SOLID/DRY, intention-revealing names, no file header comments, no explanatory comments unless a name cannot carry the meaning, no `print` in production code.
- Types used on the real-time audio thread (`AudioFormat`, `AudioLevel`, `AudioResampler`, `SampleBuffer`, `AudioCaptureError`) are declared `nonisolated`; everything else keeps the target's default `MainActor` isolation.
- Test suites touching app types are annotated `@MainActor`; fakes live in `VeyraTests/Fakes.swift`.
- Commit messages: imperative sentence (repo style), ending with the line `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Spec Refinements (decided while planning)

- `DictationState` gains `case unavailable(message: String)` for a model download/load failure (menu shows Retry; Fn ignored). `failed` stays the transient 2 s error.
- `HotkeyEvent` gains `case cancelled`, emitted when a key or another modifier is pressed while Fn is held; the coordinator discards that recording.
- Near-silent clips are dropped before transcription (Whisper hallucinates "Thank you." on silence). `TranscriptCleaner` strips Whisper non-speech tags (`[BLANK_AUDIO]`, `♪`, whole-transcript `(music)`).
- `ModelFolderCache` remembers the downloaded model folder so launches after the first never touch the network.

## Review Focus

1. **Accidental or silent Fn press** → nothing is pasted (no hallucinated "Thank you."). Pinned by `silentClipIsNotTranscribed` (Task 7) and `TranscriptCleanerTests` (Task 3).
2. **Fn used as a modifier** (Fn+←, Fn+Delete, Fn+F5) → no text is inserted and the recording is discarded. Pinned by `FnKeyTrackerTests` (Task 5) and `cancelDiscardsRecording` (Task 7).
3. **Clipboard holding an image/file or nothing** → restored exactly after the paste. Pinned by `restoresNonTextClipboard` and `restoresEmptyClipboard` (Task 4).
4. **Long dictation (minutes, "no limit")** → every captured sample reaches the transcriber; WhisperKit VAD chunking handles >30 s. Pinned by `longDictationPassesEverySample` (Task 7) plus the 2-minute manual check (Task 9).
5. **Pressing Fn again while the previous clip is still transcribing** → second press ignored, first text still inserted, state returns to idle. Pinned by `pressWhileTranscribingIsIgnored` (Task 7).

## Commands

- Build: `xcodebuild -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
- Test one suite: `xcodebuild test -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS' -only-testing:VeyraTests/<Suite> 2>&1 | grep -E "error:|Test .*(passed|failed)|TEST (SUCCEEDED|FAILED)"`
- Test all: `xcodebuild test -project Veyra.xcodeproj -scheme Veyra -destination 'platform=macOS' 2>&1 | grep -E "error:|Test .*(passed|failed)|TEST (SUCCEEDED|FAILED)"`

## File Map

```
App/VeyraApp.swift                              MenuBarExtra scene (rewrite)
App/AppDependencies.swift                       composition root
Features/Dictation/DictationState.swift         state enum
Features/Dictation/DictationState+Presentation.swift  symbol, status text, overlay visibility
Features/Dictation/DictationCoordinator.swift   state machine
Features/Dictation/MenuBarView.swift            menu contents
Features/Dictation/RecordingOverlay.swift       NSPanel controller + pill + level meter
Features/Dictation/ContentView.swift            DELETE
Services/Audio/AudioFormat.swift                16 kHz constants
Services/Audio/AudioLevel.swift                 RMS → 0...1
Services/Audio/AudioResampler.swift             AVAudioConverter wrapper
Services/Audio/SampleBuffer.swift               lock-guarded sample accumulator
Services/Audio/AudioCapturing.swift             protocol + AudioCaptureError
Services/Audio/AudioRecorder.swift              AVAudioEngine implementation (rewrite)
Services/Speech/Transcribing.swift              protocol + TranscriptionError
Services/Speech/TranscriptCleaner.swift         Whisper tag stripping
Services/Speech/ModelFolderCache.swift          UserDefaults-backed folder memo
Services/Speech/WhisperKitTranscriber.swift     WhisperKit implementation
Services/Text/TextProcessing.swift              protocol + PassthroughTextProcessor
Services/System/Pasteboard.swift                protocol + snapshot + NSPasteboard conformance
Services/System/KeystrokeSending.swift          protocol + CGEvent ⌘V
Services/System/TextInserting.swift             protocol
Services/System/PasteboardTextInserter.swift    clipboard paste + restore
Services/System/HotkeyMonitoring.swift          protocol + HotkeyEvent
Services/System/FnKeyTracker.swift              pure Fn state machine + KeyInput
Services/System/FnKeyMonitor.swift              NSEvent monitors
Services/System/Permission.swift                enum + PermissionChecking
Services/System/PermissionService.swift         TCC checks/prompts
VeyraTests/Fakes.swift                          test doubles
VeyraTests/*Tests.swift                         one file per suite
```

## Pre-flight

- [ ] Working tree is clean (the owner commits their in-progress `App/VeyraApp.swift`, `README.md`, and project-file changes first).
- [ ] Create the branch: `git switch -c feature/core-dictation`

---

### Task 1: Project configuration

Converts the app target to folder-synchronized groups (so new files need no project edits), adds WhisperKit, disables the sandbox, and sets Info.plist keys.

**Files:**
- Modify: `Veyra.xcodeproj/project.pbxproj`
- Delete: `Features/Dictation/ContentView.swift`

**Interfaces:**
- Consumes: nothing
- Produces: app target compiles every `.swift` file under `App/`, `Features/`, `Services/` and bundles `Resources/`; `import WhisperKit` available to the app target.

- [ ] **Step 1: Delete the unused view** (it calls `AudioRecorder.startRecording()`, which Task 2 removes)

```bash
git rm Features/Dictation/ContentView.swift
```

- [ ] **Step 2: Replace the `PBXBuildFile` section** with exactly:

```
/* Begin PBXBuildFile section */
		85C0FFEE0000000000000003 /* WhisperKit in Frameworks */ = {isa = PBXBuildFile; productRef = 85C0FFEE0000000000000002 /* WhisperKit */; };
/* End PBXBuildFile section */
```

- [ ] **Step 3: Replace the `PBXFileReference` section** with exactly:

```
/* Begin PBXFileReference section */
		8565516E306C563900EE41FC /* README.md */ = {isa = PBXFileReference; lastKnownFileType = net.daringfireball.markdown; path = README.md; sourceTree = "<group>"; };
		85AF98723045A3400011733D /* Veyra.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Veyra.app; sourceTree = BUILT_PRODUCTS_DIR; };
		85AF98843046CE6D0011733D /* VeyraTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = VeyraTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */
```

- [ ] **Step 4: Replace the `PBXFileSystemSynchronizedRootGroup` section** (group IDs are reused so the main group's children stay valid):

```
/* Begin PBXFileSystemSynchronizedRootGroup section */
		85AF989E3046FD120011733D /* App */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = App;
			sourceTree = "<group>";
		};
		85AF989F3046FD470011733D /* Features */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Features;
			sourceTree = "<group>";
		};
		85AF98A03046FD740011733D /* Services */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Services;
			sourceTree = "<group>";
		};
		85AF98A43046FDAA0011733D /* Resources */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Resources;
			sourceTree = "<group>";
		};
		85AF98853046CE6D0011733D /* VeyraTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = VeyraTests;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */
```

- [ ] **Step 5: In the `PBXGroup` section**, delete the six groups `App`, `Features`, `Services`, `Audio`, `Resources`, `Dictation` (IDs `85AF989E…`, `85AF989F…`, `85AF98A0…`, `85AF98A1…`, `85AF98A4…`, `85AF98A6…`). Keep the main group (`85AF98693045A3400011733D`) and `Products` unchanged.

- [ ] **Step 6: Link WhisperKit in the app's Frameworks phase** — in `85AF986F3045A3400011733D /* Frameworks */` set:

```
			files = (
				85C0FFEE0000000000000003 /* WhisperKit in Frameworks */,
			);
```

- [ ] **Step 7: Update the `Veyra` native target** (`85AF98713045A3400011733D`) — replace its empty `packageProductDependencies = ( );` and add synchronized groups, so that part reads:

```
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				85AF989E3046FD120011733D /* App */,
				85AF989F3046FD470011733D /* Features */,
				85AF98A43046FDAA0011733D /* Resources */,
				85AF98A03046FD740011733D /* Services */,
			);
			name = Veyra;
			packageProductDependencies = (
				85C0FFEE0000000000000002 /* WhisperKit */,
			);
```

- [ ] **Step 8: Empty the explicit build-phase file lists** — in `85AF98703045A3400011733D /* Resources */`, `85AF98823046CE6D0011733D /* Resources */` (this also drops `README.md` from the test bundle), and `85AF986E3045A3400011733D /* Sources */`, set `files = ( );`.

- [ ] **Step 9: Register the package on the project** — in the `PBXProject` object, after `minimizedProjectReferenceProxies = 1;` insert:

```
			packageReferences = (
				85C0FFEE0000000000000001 /* XCRemoteSwiftPackageReference "argmax-oss-swift" */,
			);
```

and before the final `	};\n	rootObject = …` line insert:

```
/* Begin XCRemoteSwiftPackageReference section */
		85C0FFEE0000000000000001 /* XCRemoteSwiftPackageReference "argmax-oss-swift" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/argmaxinc/argmax-oss-swift";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 1.1.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		85C0FFEE0000000000000002 /* WhisperKit */ = {
			isa = XCSwiftPackageProductDependency;
			package = 85C0FFEE0000000000000001 /* XCRemoteSwiftPackageReference "argmax-oss-swift" */;
			productName = WhisperKit;
		};
/* End XCSwiftPackageProductDependency section */
```

- [ ] **Step 10: App target build settings** — in both `85AF987E3045A3420011733D /* Debug */` and `85AF987F3045A3420011733D /* Release */`:
  - change `ENABLE_APP_SANDBOX = YES;` → `ENABLE_APP_SANDBOX = NO;`
  - delete `ENABLE_USER_SELECTED_FILES = readonly;`
  - add, keeping keys alphabetical:

```
				ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES;
				INFOPLIST_KEY_LSUIElement = YES;
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "Veyra listens while you hold Fn to transcribe your speech.";
```

- [ ] **Step 11: Resolve packages and build**

Run: `xcodebuild -project Veyra.xcodeproj -scheme Veyra -resolvePackageDependencies 2>&1 | tail -3`
Expected: resolved `argmax-oss-swift` at 1.x.

Run the Build command.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 12: Verify entitlements and Info.plist**

```bash
APP=$(xcodebuild -project Veyra.xcodeproj -scheme Veyra -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3}')/Veyra.app
codesign -d --entitlements - "$APP" 2>/dev/null | grep -E "audio-input|app-sandbox"
plutil -p "$APP/Contents/Info.plist" | grep -E "LSUIElement|NSMicrophoneUsageDescription"
```

Expected: `com.apple.security.device.audio-input` present with value true, no `app-sandbox` true; both Info.plist keys present.

If the audio-input entitlement is missing, create `Veyra.entitlements` at the repo root (outside the synced folders) with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.audio-input</key>
	<true/>
</dict>
</plist>
```

add `CODE_SIGN_ENTITLEMENTS = Veyra.entitlements;` to both app build configurations, rebuild, and re-run the check (then include the file in the commit).

- [ ] **Step 13: Confirm the test pipeline still runs**

Run the Test-all command.
Expected: `Test example() passed`, `TEST SUCCEEDED`.

- [ ] **Step 14: Commit**

```bash
git add Veyra.xcodeproj/project.pbxproj
git commit -m "Configure project for dictation: synced groups, WhisperKit, no sandbox

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Audio capture

**Files:**
- Create: `Services/Audio/AudioFormat.swift`, `Services/Audio/AudioLevel.swift`, `Services/Audio/AudioResampler.swift`, `Services/Audio/SampleBuffer.swift`, `Services/Audio/AudioCapturing.swift`
- Rewrite: `Services/Audio/AudioRecorder.swift`
- Delete: `VeyraTests/VeyraTests.swift`
- Test: `VeyraTests/AudioLevelTests.swift`, `VeyraTests/AudioResamplerTests.swift`, `VeyraTests/SampleBufferTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `nonisolated enum AudioFormat { static let sampleRate: Double; static let transcription: AVAudioFormat }`
  - `nonisolated enum AudioLevel { static func normalized(_ samples: [Float]) -> Float }` — 0 at ≤ −50 dBFS RMS, 1 at 0 dBFS
  - `protocol AudioCapturing: AnyObject { var levelHandler: ((Float) -> Void)? { get set }; func start() throws; func stop() -> [Float] }`
  - `final class AudioRecorder: AudioCapturing` (no-arg init)
  - `nonisolated enum AudioCaptureError: LocalizedError { case noInputDevice, unsupportedFormat }`

- [ ] **Step 1: Write failing tests**

`VeyraTests/AudioLevelTests.swift`:

```swift
import Testing
@testable import Veyra

struct AudioLevelTests {
    @Test func emptyIsSilent() {
        #expect(AudioLevel.normalized([]) == 0)
    }

    @Test func silenceIsZero() {
        #expect(AudioLevel.normalized(Array(repeating: 0, count: 1_000)) == 0)
    }

    @Test func fullScaleIsOne() {
        #expect(AudioLevel.normalized(Array(repeating: 1, count: 1_000)) == 1)
    }

    @Test func minusTwentyDecibelsMapsLinearly() {
        let level = AudioLevel.normalized(Array(repeating: 0.1, count: 1_000))
        #expect(abs(level - 0.6) < 0.001)
    }
}
```

`VeyraTests/AudioResamplerTests.swift`:

```swift
import AVFoundation
import Testing
@testable import Veyra

struct AudioResamplerTests {
    private let stereo48k = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    @Test func convertsStereo48kToMono16k() throws {
        let resampler = try AudioResampler(inputFormat: stereo48k)
        let total = try (0..<10).reduce(0) { count, _ in
            count + (try resampler.convert(sine(frames: 4_800))).count
        }
        #expect(abs(total - 16_000) < 200)
    }

    @Test func preservesSignal() throws {
        let resampler = try AudioResampler(inputFormat: stereo48k)
        let output = try (0..<3).flatMap { _ in try resampler.convert(sine(frames: 4_800)) }
        #expect((output.max() ?? 0) > 0.4)
    }

    private func sine(frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: stereo48k, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(stereo48k.channelCount) {
            let data = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                data[frame] = 0.5 * sin(2 * .pi * 440 * Float(frame) / 48_000)
            }
        }
        return buffer
    }
}
```

`VeyraTests/SampleBufferTests.swift`:

```swift
import Testing
@testable import Veyra

struct SampleBufferTests {
    @Test func drainReturnsAppendedSamplesInOrder() {
        let buffer = SampleBuffer()
        buffer.append([1, 2])
        buffer.append([3])
        #expect(buffer.drain() == [1, 2, 3])
    }

    @Test func drainEmptiesTheBuffer() {
        let buffer = SampleBuffer()
        buffer.append([1])
        _ = buffer.drain()
        #expect(buffer.drain().isEmpty)
    }
}
```

Delete the placeholder: `git rm VeyraTests/VeyraTests.swift`

- [ ] **Step 2: Run tests to verify they fail**

Run the Test-all command.
Expected: build error `cannot find 'AudioLevel' in scope` (and `AudioResampler`, `SampleBuffer`).

- [ ] **Step 3: Implement**

`Services/Audio/AudioFormat.swift`:

```swift
import AVFoundation

nonisolated enum AudioFormat {
    static let sampleRate: Double = 16_000
    static let transcription = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!
}
```

`Services/Audio/AudioLevel.swift`:

```swift
import Accelerate

nonisolated enum AudioLevel {
    private static let floorDecibels: Float = -50

    static func normalized(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let decibels = 10 * log10(max(vDSP.meanSquare(samples), 1e-10))
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}
```

`Services/Audio/AudioCapturing.swift`:

```swift
import Foundation

protocol AudioCapturing: AnyObject {
    var levelHandler: ((Float) -> Void)? { get set }
    func start() throws
    func stop() -> [Float]
}

nonisolated enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone available"
        case .unsupportedFormat: "Microphone format not supported"
        }
    }
}
```

`Services/Audio/SampleBuffer.swift`:

```swift
import Foundation

nonisolated final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        lock.withLock { samples += newSamples }
    }

    func drain() -> [Float] {
        lock.withLock {
            defer { samples = [] }
            return samples
        }
    }
}
```

`Services/Audio/AudioResampler.swift`:

```swift
import AVFoundation

nonisolated final class AudioResampler: @unchecked Sendable {
    private let converter: AVAudioConverter

    init(inputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: AudioFormat.transcription) else {
            throw AudioCaptureError.unsupportedFormat
        }
        converter.downmix = true
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let ratio = AudioFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: AudioFormat.transcription, frameCapacity: capacity) else {
            throw AudioCaptureError.unsupportedFormat
        }

        nonisolated(unsafe) var isConsumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard !isConsumed else {
                status.pointee = .noDataNow
                return nil
            }
            isConsumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }

        guard let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
```

`Services/Audio/AudioRecorder.swift` (replace the whole file):

```swift
import AVFoundation

final class AudioRecorder: AudioCapturing {
    var levelHandler: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let buffer = SampleBuffer()

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        let tap = Self.makeTap(resampler: try AudioResampler(inputFormat: format), buffer: buffer) { [weak self] level in
            Task { @MainActor in self?.levelHandler?(level) }
        }
        input.installTap(onBus: 0, bufferSize: 4_096, format: format, block: tap)
        engine.prepare()

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return buffer.drain()
    }

    private nonisolated static func makeTap(
        resampler: AudioResampler,
        buffer: SampleBuffer,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { pcm, _ in
            guard let samples = try? resampler.convert(pcm), !samples.isEmpty else { return }
            buffer.append(samples)
            onLevel(AudioLevel.normalized(samples))
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Test-all command.
Expected: all 8 tests in `AudioLevelTests`, `AudioResamplerTests`, `SampleBufferTests` pass; `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Services/Audio VeyraTests
git commit -m "Capture microphone audio as 16 kHz mono samples with level metering

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Speech transcription

**Files:**
- Create: `Services/Speech/Transcribing.swift`, `Services/Speech/TranscriptCleaner.swift`, `Services/Speech/ModelFolderCache.swift`, `Services/Speech/WhisperKitTranscriber.swift`
- Test: `VeyraTests/TranscriptCleanerTests.swift`, `VeyraTests/ModelFolderCacheTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `protocol Transcribing { func prepare(progress: @escaping @MainActor (Double) -> Void) async throws; func transcribe(_ samples: [Float]) async throws -> String }` — `transcribe` returns cleaned, trimmed text (possibly empty)
  - `enum TranscriptCleaner { static func clean(_ raw: String) -> String }`
  - `struct ModelFolderCache { init(defaults: UserDefaults, key: String); var folder: URL? { get }; func store(_ folder: URL); func clear() }`
  - `final class WhisperKitTranscriber: Transcribing` — `init(variant: String = "large-v3-v20240930_turbo", downloadBase: URL = .applicationSupportDirectory.appending(path: "Veyra/Models"), defaults: UserDefaults = .standard)`

- [ ] **Step 1: Write failing tests**

`VeyraTests/TranscriptCleanerTests.swift`:

```swift
import Testing
@testable import Veyra

@MainActor
struct TranscriptCleanerTests {
    @Test(arguments: [
        ("[BLANK_AUDIO]", ""),
        ("  Hello   world.  ", "Hello world."),
        ("Hello [MUSIC] there", "Hello there"),
        ("♪ ♪", ""),
        ("(upbeat music)", ""),
        ("*sighs*", ""),
        ("Call me (maybe) later", "Call me (maybe) later"),
    ])
    func cleans(raw: String, expected: String) {
        #expect(TranscriptCleaner.clean(raw) == expected)
    }
}
```

`VeyraTests/ModelFolderCacheTests.swift`:

```swift
import Foundation
import Testing
@testable import Veyra

@MainActor
struct ModelFolderCacheTests {
    private let defaults = UserDefaults(suiteName: "ModelFolderCacheTests.\(UUID().uuidString)")!
    private var cache: ModelFolderCache { ModelFolderCache(defaults: defaults, key: "folder") }

    @Test func returnsStoredExistingFolder() {
        let folder = FileManager.default.temporaryDirectory
        cache.store(folder)
        #expect(cache.folder?.standardizedFileURL == folder.standardizedFileURL)
    }

    @Test func ignoresFolderThatNoLongerExists() {
        cache.store(URL(filePath: "/nonexistent/\(UUID().uuidString)"))
        #expect(cache.folder == nil)
    }

    @Test func clearForgetsFolder() {
        cache.store(FileManager.default.temporaryDirectory)
        cache.clear()
        #expect(cache.folder == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: Test one suite with `<Suite>` = `TranscriptCleanerTests`
Expected: build error `cannot find 'TranscriptCleaner' in scope`.

- [ ] **Step 3: Implement**

`Services/Speech/Transcribing.swift`:

```swift
import Foundation

protocol Transcribing {
    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? { "Speech model is not loaded" }
}
```

`Services/Speech/TranscriptCleaner.swift`:

```swift
import Foundation

enum TranscriptCleaner {
    static func clean(_ raw: String) -> String {
        let text = raw
            .replacing(#/\[[^\]]*\]|♪/#, with: "")
            .replacing(#/\s+/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isAnnotation(text) ? "" : text
    }

    private static func isAnnotation(_ text: String) -> Bool {
        text.wholeMatch(of: #/\(.*\)|\*.*\*/#) != nil
    }
}
```

`Services/Speech/ModelFolderCache.swift`:

```swift
import Foundation

struct ModelFolderCache {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    var folder: URL? {
        guard let path = defaults.string(forKey: key), FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(filePath: path)
    }

    func store(_ folder: URL) {
        defaults.set(folder.path, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
```

`Services/Speech/WhisperKitTranscriber.swift`:

```swift
import Foundation
import WhisperKit

final class WhisperKitTranscriber: Transcribing {
    private static let decodingOptions = DecodingOptions(
        detectLanguage: true,
        skipSpecialTokens: true,
        withoutTimestamps: true,
        chunkingStrategy: .vad
    )

    private let variant: String
    private let downloadBase: URL
    private let cache: ModelFolderCache
    private var whisperKit: WhisperKit?

    init(
        variant: String = "large-v3-v20240930_turbo",
        downloadBase: URL = .applicationSupportDirectory.appending(path: "Veyra/Models"),
        defaults: UserDefaults = .standard
    ) {
        self.variant = variant
        self.downloadBase = downloadBase
        self.cache = ModelFolderCache(defaults: defaults, key: "modelFolder.\(variant)")
    }

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        let folder = try await modelFolder(progress: progress)
        do {
            whisperKit = try await WhisperKit(WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: downloadBase,
                verbose: false,
                logLevel: .error,
                load: true,
                download: false
            ))
        } catch {
            cache.clear()
            throw error
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: Self.decodingOptions)
        return TranscriptCleaner.clean(results.map(\.text).joined(separator: " "))
    }

    private func modelFolder(progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        if let cached = cache.folder { return cached }
        let folder = try await WhisperKit.download(variant: variant, downloadBase: downloadBase) { update in
            let fraction = update.fractionCompleted
            Task { @MainActor in progress(fraction) }
        }
        cache.store(folder)
        return folder
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: Test one suite with `TranscriptCleanerTests`, then with `ModelFolderCacheTests`.
Expected: 7 + 3 tests pass. Also run the Build command → `BUILD SUCCEEDED` (proves the WhisperKit API calls compile).

- [ ] **Step 5: Commit**

```bash
git add Services/Speech VeyraTests
git commit -m "Transcribe audio locally with WhisperKit large-v3-turbo

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Text processing and insertion

**Files:**
- Create: `Services/Text/TextProcessing.swift`, `Services/System/Pasteboard.swift`, `Services/System/KeystrokeSending.swift`, `Services/System/TextInserting.swift`, `Services/System/PasteboardTextInserter.swift`, `VeyraTests/Fakes.swift`
- Test: `VeyraTests/PasteboardTextInserterTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `protocol TextProcessing { func process(_ text: String) async throws -> String }`, `struct PassthroughTextProcessor: TextProcessing`
  - `struct PasteboardSnapshot: Equatable { var items: [[String: Data]] }`
  - `protocol Pasteboard: AnyObject { var changeCount: Int { get }; func snapshot() -> PasteboardSnapshot; func restore(_ snapshot: PasteboardSnapshot); func write(_ text: String) }`; `NSPasteboard: Pasteboard`
  - `protocol KeystrokeSending { func sendPaste() }`, `struct CGEventKeystrokeSender: KeystrokeSending`
  - `protocol TextInserting { func insert(_ text: String) async throws }`
  - `final class PasteboardTextInserter: TextInserting` — `init(pasteboard: Pasteboard, keystrokes: KeystrokeSending, restoreDelay: Duration = .milliseconds(250))`
  - `VeyraTests/Fakes.swift`: `FakePasteboard`, `FakeKeystrokes` (Task 7 appends more fakes to this file)

- [ ] **Step 1: Write fakes and failing tests**

`VeyraTests/Fakes.swift`:

```swift
import Foundation
@testable import Veyra

@MainActor
final class FakePasteboard: Pasteboard {
    static let textType = "public.utf8-plain-text"

    private(set) var changeCount = 0
    var items: [[String: Data]] = []

    var string: String? {
        items.first?[Self.textType].flatMap { String(data: $0, encoding: .utf8) }
    }

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: items)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        items = snapshot.items
        changeCount += 1
    }

    func write(_ text: String) {
        items = [[Self.textType: Data(text.utf8)]]
        changeCount += 1
    }
}

@MainActor
final class FakeKeystrokes: KeystrokeSending {
    private let pasteboard: FakePasteboard
    var sideEffect: () -> Void = {}
    private(set) var pastedTexts: [String?] = []

    init(pasteboard: FakePasteboard) {
        self.pasteboard = pasteboard
    }

    func sendPaste() {
        pastedTexts.append(pasteboard.string)
        sideEffect()
    }
}
```

`VeyraTests/PasteboardTextInserterTests.swift`:

```swift
import Foundation
import Testing
@testable import Veyra

@MainActor
struct PasteboardTextInserterTests {
    private let pasteboard = FakePasteboard()
    private let keystrokes: FakeKeystrokes
    private let inserter: PasteboardTextInserter

    init() {
        keystrokes = FakeKeystrokes(pasteboard: pasteboard)
        inserter = PasteboardTextInserter(pasteboard: pasteboard, keystrokes: keystrokes, restoreDelay: .zero)
    }

    @Test func pastesTextThenRestoresClipboard() async throws {
        pasteboard.write("old")
        try await inserter.insert("hello")
        #expect(keystrokes.pastedTexts == ["hello"])
        #expect(pasteboard.string == "old")
    }

    @Test func restoresNonTextClipboard() async throws {
        let original: [[String: Data]] = [
            ["public.png": Data([1, 2, 3]), "public.tiff": Data([4])],
            ["public.file-url": Data("file:///tmp/a".utf8)],
        ]
        pasteboard.items = original
        try await inserter.insert("hello")
        #expect(pasteboard.items == original)
    }

    @Test func restoresEmptyClipboard() async throws {
        try await inserter.insert("hello")
        #expect(pasteboard.items.isEmpty)
    }

    @Test func keepsClipboardChangedByAnotherApp() async throws {
        pasteboard.write("old")
        keystrokes.sideEffect = { [pasteboard] in pasteboard.write("copied elsewhere") }
        try await inserter.insert("hello")
        #expect(pasteboard.string == "copied elsewhere")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: Test one suite with `PasteboardTextInserterTests`
Expected: build error `cannot find type 'Pasteboard' in scope`.

- [ ] **Step 3: Implement**

`Services/Text/TextProcessing.swift`:

```swift
protocol TextProcessing {
    func process(_ text: String) async throws -> String
}

struct PassthroughTextProcessor: TextProcessing {
    func process(_ text: String) async throws -> String { text }
}
```

`Services/System/Pasteboard.swift`:

```swift
import AppKit

struct PasteboardSnapshot: Equatable {
    var items: [[String: Data]]
}

protocol Pasteboard: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    func write(_ text: String)
}

extension NSPasteboard: Pasteboard {
    private static let transientType = PasteboardType("org.nspasteboard.TransientType")

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: (pasteboardItems ?? []).map { item in
            item.types.reduce(into: [:]) { contents, type in
                contents[type.rawValue] = item.data(forType: type)
            }
        })
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        clearContents()
        writeObjects(snapshot.items.map { contents in
            let item = NSPasteboardItem()
            contents.forEach { type, data in item.setData(data, forType: PasteboardType(type)) }
            return item
        })
    }

    func write(_ text: String) {
        clearContents()
        setString(text, forType: .string)
        setData(Data(), forType: Self.transientType)
    }
}
```

`Services/System/KeystrokeSending.swift`:

```swift
import Carbon.HIToolbox
import CoreGraphics

protocol KeystrokeSending {
    func sendPaste()
}

struct CGEventKeystrokeSender: KeystrokeSending {
    func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isKeyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isKeyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
```

`Services/System/TextInserting.swift`:

```swift
protocol TextInserting {
    func insert(_ text: String) async throws
}
```

`Services/System/PasteboardTextInserter.swift`:

```swift
import Foundation

final class PasteboardTextInserter: TextInserting {
    private let pasteboard: Pasteboard
    private let keystrokes: KeystrokeSending
    private let restoreDelay: Duration

    init(pasteboard: Pasteboard, keystrokes: KeystrokeSending, restoreDelay: Duration = .milliseconds(250)) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.restoreDelay = restoreDelay
    }

    func insert(_ text: String) async throws {
        let original = pasteboard.snapshot()
        pasteboard.write(text)
        let ownChange = pasteboard.changeCount
        keystrokes.sendPaste()
        try await Task.sleep(for: restoreDelay)
        guard pasteboard.changeCount == ownChange else { return }
        pasteboard.restore(original)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: Test one suite with `PasteboardTextInserterTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Services/Text Services/System VeyraTests
git commit -m "Insert text via clipboard paste and restore the previous clipboard

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Fn hotkey

**Files:**
- Create: `Services/System/HotkeyMonitoring.swift`, `Services/System/FnKeyTracker.swift`, `Services/System/FnKeyMonitor.swift`
- Test: `VeyraTests/FnKeyTrackerTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum HotkeyEvent: Equatable { case pressed, released, cancelled }`
  - `protocol HotkeyMonitoring: AnyObject { var handler: ((HotkeyEvent) -> Void)? { get set }; func start(); func stop() }` — `start()` is idempotent (restarts)
  - `enum KeyInput: Equatable { case flagsChanged(fn: Bool, otherModifiers: Bool); case keyDown }`
  - `struct FnKeyTracker { mutating func handle(_ input: KeyInput) -> HotkeyEvent? }`
  - `final class FnKeyMonitor: HotkeyMonitoring` (no-arg init)

- [ ] **Step 1: Write failing tests**

`VeyraTests/FnKeyTrackerTests.swift`:

```swift
import Testing
@testable import Veyra

@MainActor
struct FnKeyTrackerTests {
    private let fnDown = KeyInput.flagsChanged(fn: true, otherModifiers: false)
    private let fnUp = KeyInput.flagsChanged(fn: false, otherModifiers: false)

    private func events(_ inputs: [KeyInput]) -> [HotkeyEvent] {
        var tracker = FnKeyTracker()
        return inputs.compactMap { tracker.handle($0) }
    }

    @Test func pressAndRelease() {
        #expect(events([fnDown, fnUp]) == [.pressed, .released])
    }

    @Test func fnWithAnotherModifierDoesNotPress() {
        #expect(events([.flagsChanged(fn: true, otherModifiers: true), fnUp]).isEmpty)
    }

    @Test func keyDownWhileHeldCancelsOnce() {
        #expect(events([fnDown, .keyDown, .keyDown, fnUp]) == [.pressed, .cancelled])
    }

    @Test func addingModifierWhileHeldCancels() {
        #expect(events([fnDown, .flagsChanged(fn: true, otherModifiers: true), fnUp]) == [.pressed, .cancelled])
    }

    @Test func keyDownWithoutFnIsIgnored() {
        #expect(events([.keyDown]).isEmpty)
    }

    @Test func worksAgainAfterCancelledPress() {
        #expect(events([fnDown, .keyDown, fnUp, fnDown, fnUp]) == [.pressed, .cancelled, .pressed, .released])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: Test one suite with `FnKeyTrackerTests`
Expected: build error `cannot find type 'KeyInput' in scope`.

- [ ] **Step 3: Implement**

`Services/System/HotkeyMonitoring.swift`:

```swift
enum HotkeyEvent: Equatable {
    case pressed
    case released
    case cancelled
}

protocol HotkeyMonitoring: AnyObject {
    var handler: ((HotkeyEvent) -> Void)? { get set }
    func start()
    func stop()
}
```

`Services/System/FnKeyTracker.swift`:

```swift
enum KeyInput: Equatable {
    case flagsChanged(fn: Bool, otherModifiers: Bool)
    case keyDown
}

struct FnKeyTracker {
    private var isHeld = false
    private var isCancelled = false

    mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fn: true, otherModifiers: false) where !isHeld:
            isHeld = true
            isCancelled = false
            return .pressed
        case .flagsChanged(fn: false, otherModifiers: _) where isHeld:
            isHeld = false
            return isCancelled ? nil : .released
        case .flagsChanged(fn: true, otherModifiers: true) where isHeld, .keyDown where isHeld:
            return cancel()
        default:
            return nil
        }
    }

    private mutating func cancel() -> HotkeyEvent? {
        guard !isCancelled else { return nil }
        isCancelled = true
        return .cancelled
    }
}
```

`Services/System/FnKeyMonitor.swift`:

```swift
import AppKit

final class FnKeyMonitor: HotkeyMonitoring {
    var handler: ((HotkeyEvent) -> Void)?

    private var tracker = FnKeyTracker()
    private var monitors: [Any] = []

    func start() {
        stop()
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.process(event)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.process(event)
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        tracker = FnKeyTracker()
    }

    private func process(_ event: NSEvent) {
        guard let input = KeyInput(event), let hotkeyEvent = tracker.handle(input) else { return }
        handler?(hotkeyEvent)
    }
}

private extension KeyInput {
    init?(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            self = .keyDown
        case .flagsChanged:
            let flags = event.modifierFlags
            self = .flagsChanged(
                fn: flags.contains(.function),
                otherModifiers: !flags.isDisjoint(with: [.shift, .control, .option, .command])
            )
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: Test one suite with `FnKeyTrackerTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Services/System VeyraTests
git commit -m "Detect hold-to-talk Fn presses and cancel when Fn is used as a modifier

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Permission model

Kept separate from the coordinator so the coordinator depends only on the narrow `PermissionChecking` interface (ISP).

**Files:**
- Create: `Services/System/Permission.swift`, `Services/System/PermissionService.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum Permission: CaseIterable, Identifiable { case microphone, accessibility; var title: String; var settingsURL: URL }`
  - `protocol PermissionChecking { func isGranted(_ permission: Permission) -> Bool }`
  - `@Observable final class PermissionService: PermissionChecking` — `private(set) var missing: [Permission]`, `func requestInitialAccess() async`, `func request(_ permission: Permission) async`, `func monitor(onChange: () -> Void) async`

- [ ] **Step 1: Implement** (system TCC APIs; verified manually in Task 9)

`Services/System/Permission.swift`:

```swift
import Foundation

enum Permission: CaseIterable, Identifiable {
    case microphone
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        }
    }

    var settingsURL: URL {
        let pane = switch self {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}

protocol PermissionChecking {
    func isGranted(_ permission: Permission) -> Bool
}
```

`Services/System/PermissionService.swift`:

```swift
import AppKit
import ApplicationServices
import AVFoundation
import Observation

@Observable
final class PermissionService: PermissionChecking {
    private(set) var missing: [Permission] = []

    init() {
        refresh()
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: AXIsProcessTrusted()
        }
    }

    func requestInitialAccess() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            await request(.microphone)
        }
        if !isGranted(.accessibility) {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    func request(_ permission: Permission) async {
        switch permission {
        case .microphone where AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            NSWorkspace.shared.open(permission.settingsURL)
        }
        refresh()
    }

    func monitor(onChange: () -> Void) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            let previous = missing
            refresh()
            if missing != previous { onChange() }
        }
    }

    private func refresh() {
        missing = Permission.allCases.filter { !isGranted($0) }
    }
}
```

- [ ] **Step 2: Build**

Run the Build command.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Services/System
git commit -m "Check and request microphone and accessibility permissions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Dictation coordinator

**Files:**
- Create: `Features/Dictation/DictationState.swift`, `Features/Dictation/DictationCoordinator.swift`
- Modify: `VeyraTests/Fakes.swift` (append)
- Test: `VeyraTests/DictationCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AudioCapturing`, `AudioFormat.sampleRate`, `AudioLevel.normalized` (Task 2); `Transcribing` (Task 3); `TextProcessing`, `PassthroughTextProcessor`, `TextInserting` (Task 4); `HotkeyMonitoring`, `HotkeyEvent` (Task 5); `Permission`, `PermissionChecking` (Task 6)
- Produces:
  - `enum DictationState: Equatable { case preparing(progress: Double?), idle, recording(level: Float), transcribing, failed(message: String), unavailable(message: String) }`
  - `@Observable final class DictationCoordinator` — `init(audio:transcriber:processor:inserter:hotkey:permissions:failureDisplayDuration: Duration = .seconds(2))`, `private(set) var state: DictationState`, `func start() async`, `func prepareModel() async`, `func reconnectHotkey()`, `func handle(_ event: HotkeyEvent)`, test hooks `private(set) var transcription: Task<Void, Never>?` and `private(set) var recovery: Task<Void, Never>?`

- [ ] **Step 1: Append fakes** to `VeyraTests/Fakes.swift`:

```swift
struct TestError: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
final class FakeAudio: AudioCapturing {
    var levelHandler: ((Float) -> Void)?
    var samples: [Float] = Array(repeating: 0.1, count: 16_000)
    var startError: Error?
    private(set) var isRecording = false

    func start() throws {
        if let startError { throw startError }
        isRecording = true
    }

    func stop() -> [Float] {
        isRecording = false
        return samples
    }
}

@MainActor
final class FakeTranscriber: Transcribing {
    var transcript = "hello world"
    var prepareError: Error?
    var transcribeError: Error?
    private(set) var receivedSamples: [Float]?
    private(set) var progressHandler: (@MainActor (Double) -> Void)?

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        progressHandler = progress
        if let prepareError { throw prepareError }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        receivedSamples = samples
        if let transcribeError { throw transcribeError }
        return transcript
    }
}

struct UppercasingProcessor: TextProcessing {
    func process(_ text: String) async throws -> String { text.uppercased() }
}

@MainActor
final class FakeInserter: TextInserting {
    private(set) var inserted: [String] = []

    func insert(_ text: String) async throws {
        inserted.append(text)
    }
}

@MainActor
final class FakeHotkey: HotkeyMonitoring {
    var handler: ((HotkeyEvent) -> Void)?
    private(set) var startCount = 0

    func start() { startCount += 1 }
    func stop() {}

    func send(_ events: HotkeyEvent...) {
        events.forEach { handler?($0) }
    }
}

@MainActor
final class FakePermissions: PermissionChecking {
    var denied: Set<Permission> = []

    func isGranted(_ permission: Permission) -> Bool { !denied.contains(permission) }
}
```

- [ ] **Step 2: Write failing tests**

`VeyraTests/DictationCoordinatorTests.swift`:

```swift
import Testing
@testable import Veyra

@MainActor
struct DictationCoordinatorTests {
    private let audio = FakeAudio()
    private let transcriber = FakeTranscriber()
    private let inserter = FakeInserter()
    private let hotkey = FakeHotkey()
    private let permissions = FakePermissions()

    private func readyCoordinator(
        processor: TextProcessing = PassthroughTextProcessor(),
        failureDisplayDuration: Duration = .seconds(60)
    ) async -> DictationCoordinator {
        let coordinator = DictationCoordinator(
            audio: audio,
            transcriber: transcriber,
            processor: processor,
            inserter: inserter,
            hotkey: hotkey,
            permissions: permissions,
            failureDisplayDuration: failureDisplayDuration
        )
        await coordinator.start()
        return coordinator
    }

    private func dictate(_ coordinator: DictationCoordinator) async {
        hotkey.send(.pressed, .released)
        await coordinator.transcription?.value
    }

    @Test func becomesIdleWhenModelIsReady() async {
        let coordinator = await readyCoordinator()
        #expect(coordinator.state == .idle)
        #expect(hotkey.startCount == 1)
    }

    @Test func modelFailureMakesDictationUnavailable() async {
        transcriber.prepareError = TestError()
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed)
        #expect(coordinator.state == .unavailable(message: "boom"))
        #expect(!audio.isRecording)
    }

    @Test func retryAfterModelFailure() async {
        transcriber.prepareError = TestError()
        let coordinator = await readyCoordinator()
        transcriber.prepareError = nil
        await coordinator.prepareModel()
        #expect(coordinator.state == .idle)
    }

    @Test func lateProgressDoesNotLeaveIdle() async {
        let coordinator = await readyCoordinator()
        transcriber.progressHandler?(0.9)
        #expect(coordinator.state == .idle)
    }

    @Test func pressStartsRecordingAndReportsLevel() async {
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed)
        audio.levelHandler?(0.7)
        #expect(audio.isRecording)
        #expect(coordinator.state == .recording(level: 0.7))
    }

    @Test func levelIgnoredWhenNotRecording() async {
        let coordinator = await readyCoordinator()
        audio.levelHandler?(0.7)
        #expect(coordinator.state == .idle)
    }

    @Test func dictationInsertsTranscript() async {
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(inserter.inserted == ["hello world"])
        #expect(coordinator.state == .idle)
    }

    @Test func insertsProcessedText() async {
        let coordinator = await readyCoordinator(processor: UppercasingProcessor())
        await dictate(coordinator)
        #expect(inserter.inserted == ["HELLO WORLD"])
    }

    @Test func longDictationPassesEverySample() async {
        audio.samples = Array(repeating: 0.1, count: 16_000 * 120)
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(transcriber.receivedSamples?.count == 16_000 * 120)
    }

    @Test func shortClipIsNotTranscribed() async {
        audio.samples = Array(repeating: 0.1, count: 1_000)
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(transcriber.receivedSamples == nil)
        #expect(coordinator.state == .idle)
    }

    @Test func silentClipIsNotTranscribed() async {
        audio.samples = Array(repeating: 0, count: 16_000)
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(transcriber.receivedSamples == nil)
        #expect(inserter.inserted.isEmpty)
    }

    @Test func emptyTranscriptIsNotInserted() async {
        transcriber.transcript = ""
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(inserter.inserted.isEmpty)
        #expect(coordinator.state == .idle)
    }

    @Test func pressWhileTranscribingIsIgnored() async {
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed, .released, .pressed)
        #expect(coordinator.state == .transcribing)
        #expect(!audio.isRecording)
        await coordinator.transcription?.value
        #expect(inserter.inserted == ["hello world"])
        #expect(coordinator.state == .idle)
    }

    @Test func cancelDiscardsRecording() async {
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed, .cancelled)
        #expect(!audio.isRecording)
        #expect(coordinator.state == .idle)
        #expect(transcriber.receivedSamples == nil)
    }

    @Test func missingPermissionBlocksRecording() async {
        permissions.denied = [.accessibility]
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed)
        #expect(!audio.isRecording)
        #expect(coordinator.state == .failed(message: "Accessibility access is required"))
    }

    @Test func audioStartErrorShowsFailure() async {
        audio.startError = TestError()
        let coordinator = await readyCoordinator()
        hotkey.send(.pressed)
        #expect(coordinator.state == .failed(message: "boom"))
    }

    @Test func transcriptionErrorShowsFailure() async {
        transcriber.transcribeError = TestError()
        let coordinator = await readyCoordinator()
        await dictate(coordinator)
        #expect(coordinator.state == .failed(message: "boom"))
        #expect(inserter.inserted.isEmpty)
    }

    @Test func failureReturnsToIdle() async {
        transcriber.transcribeError = TestError()
        let coordinator = await readyCoordinator(failureDisplayDuration: .zero)
        await dictate(coordinator)
        await coordinator.recovery?.value
        #expect(coordinator.state == .idle)
    }

    @Test func reconnectHotkeyRestartsMonitor() async {
        let coordinator = await readyCoordinator()
        coordinator.reconnectHotkey()
        #expect(hotkey.startCount == 2)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: Test one suite with `DictationCoordinatorTests`
Expected: build error `cannot find 'DictationCoordinator' in scope`.

- [ ] **Step 4: Implement**

`Features/Dictation/DictationState.swift`:

```swift
enum DictationState: Equatable {
    case preparing(progress: Double?)
    case idle
    case recording(level: Float)
    case transcribing
    case failed(message: String)
    case unavailable(message: String)
}
```

`Features/Dictation/DictationCoordinator.swift`:

```swift
import Foundation
import Observation

@Observable
final class DictationCoordinator {
    private static let minimumSampleCount = Int(AudioFormat.sampleRate * 0.3)
    private static let silenceLevel: Float = 0.1

    private(set) var state: DictationState = .preparing(progress: nil)
    @ObservationIgnored private(set) var transcription: Task<Void, Never>?
    @ObservationIgnored private(set) var recovery: Task<Void, Never>?

    private let audio: AudioCapturing
    private let transcriber: Transcribing
    private let processor: TextProcessing
    private let inserter: TextInserting
    private let hotkey: HotkeyMonitoring
    private let permissions: PermissionChecking
    private let failureDisplayDuration: Duration

    init(
        audio: AudioCapturing,
        transcriber: Transcribing,
        processor: TextProcessing,
        inserter: TextInserting,
        hotkey: HotkeyMonitoring,
        permissions: PermissionChecking,
        failureDisplayDuration: Duration = .seconds(2)
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.processor = processor
        self.inserter = inserter
        self.hotkey = hotkey
        self.permissions = permissions
        self.failureDisplayDuration = failureDisplayDuration
    }

    func start() async {
        hotkey.handler = { [weak self] event in self?.handle(event) }
        audio.levelHandler = { [weak self] level in self?.updateLevel(level) }
        hotkey.start()
        await prepareModel()
    }

    func prepareModel() async {
        state = .preparing(progress: nil)
        do {
            try await transcriber.prepare { [weak self] progress in self?.updateProgress(progress) }
            state = .idle
        } catch {
            state = .unavailable(message: error.localizedDescription)
        }
    }

    func reconnectHotkey() {
        hotkey.start()
    }

    func handle(_ event: HotkeyEvent) {
        switch (event, state) {
        case (.pressed, .idle): beginRecording()
        case (.released, .recording): finishRecording()
        case (.cancelled, .recording): cancelRecording()
        default: break
        }
    }

    private func beginRecording() {
        if let missing = Permission.allCases.first(where: { !permissions.isGranted($0) }) {
            return fail("\(missing.title) access is required")
        }
        do {
            try audio.start()
            state = .recording(level: 0)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func finishRecording() {
        let samples = audio.stop()
        guard isWorthTranscribing(samples) else {
            state = .idle
            return
        }
        state = .transcribing
        transcription = Task { await transcribeAndInsert(samples) }
    }

    private func cancelRecording() {
        _ = audio.stop()
        state = .idle
    }

    private func transcribeAndInsert(_ samples: [Float]) async {
        do {
            let transcript = try await transcriber.transcribe(samples)
            if !transcript.isEmpty {
                try await inserter.insert(try await processor.process(transcript))
            }
            state = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        state = .failed(message: message)
        recovery = Task { [failureDisplayDuration] in
            try? await Task.sleep(for: failureDisplayDuration)
            if state == .failed(message: message) { state = .idle }
        }
    }

    private func isWorthTranscribing(_ samples: [Float]) -> Bool {
        samples.count >= Self.minimumSampleCount && AudioLevel.normalized(samples) > Self.silenceLevel
    }

    private func updateLevel(_ level: Float) {
        if case .recording = state { state = .recording(level: level) }
    }

    private func updateProgress(_ progress: Double) {
        if case .preparing = state { state = .preparing(progress: progress) }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: Test one suite with `DictationCoordinatorTests`
Expected: 19 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Features/Dictation VeyraTests
git commit -m "Drive the dictation pipeline with a coordinator state machine

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Menu bar and overlay UI

**Files:**
- Create: `Features/Dictation/DictationState+Presentation.swift`, `Features/Dictation/MenuBarView.swift`, `Features/Dictation/RecordingOverlay.swift`
- Test: `VeyraTests/DictationStatePresentationTests.swift`

**Interfaces:**
- Consumes: `DictationState`, `DictationCoordinator` (Task 7); `PermissionService`, `Permission` (Task 6)
- Produces:
  - `extension DictationState { var menuBarSymbol: String; var statusText: String; var showsOverlay: Bool }`
  - `struct MenuBarView: View` — `init(coordinator: DictationCoordinator, permissions: PermissionService)`
  - `final class RecordingOverlayController` — `init(coordinator: DictationCoordinator)`, `func start()`

- [ ] **Step 1: Write failing tests**

`VeyraTests/DictationStatePresentationTests.swift`:

```swift
import Testing
@testable import Veyra

@MainActor
struct DictationStatePresentationTests {
    @Test(arguments: [
        (DictationState.preparing(progress: nil), "Loading speech model…"),
        (.preparing(progress: 0.42), "Downloading speech model… 42%"),
        (.preparing(progress: 1), "Loading speech model…"),
        (.idle, "Hold Fn to dictate"),
        (.unavailable(message: "Offline"), "Offline"),
    ])
    func statusText(state: DictationState, expected: String) {
        #expect(state.statusText == expected)
    }

    @Test(arguments: [
        (DictationState.recording(level: 0), true),
        (.transcribing, true),
        (.failed(message: "x"), true),
        (.idle, false),
        (.preparing(progress: nil), false),
        (.unavailable(message: "x"), false),
    ])
    func overlayVisibility(state: DictationState, expected: Bool) {
        #expect(state.showsOverlay == expected)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: Test one suite with `DictationStatePresentationTests`
Expected: build error `value of type 'DictationState' has no member 'statusText'`.

- [ ] **Step 3: Implement**

`Features/Dictation/DictationState+Presentation.swift`:

```swift
extension DictationState {
    var menuBarSymbol: String {
        switch self {
        case .preparing, .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        case .failed, .unavailable: "exclamationmark.triangle"
        }
    }

    var statusText: String {
        switch self {
        case .preparing(let progress?) where progress < 1: "Downloading speech model… \(Int(progress * 100))%"
        case .preparing: "Loading speech model…"
        case .idle: "Hold Fn to dictate"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .failed(let message), .unavailable(let message): message
        }
    }

    var showsOverlay: Bool {
        switch self {
        case .recording, .transcribing, .failed: true
        case .preparing, .idle, .unavailable: false
        }
    }
}
```

`Features/Dictation/MenuBarView.swift`:

```swift
import AppKit
import SwiftUI

struct MenuBarView: View {
    let coordinator: DictationCoordinator
    let permissions: PermissionService

    var body: some View {
        Text(coordinator.state.statusText)
        if case .unavailable = coordinator.state {
            Button("Retry") { Task { await coordinator.prepareModel() } }
        }
        if !permissions.missing.isEmpty {
            Divider()
            ForEach(permissions.missing) { permission in
                Button("Grant \(permission.title) Access…") { Task { await permissions.request(permission) } }
            }
        }
        Divider()
        Button("Quit Veyra") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
```

`Features/Dictation/RecordingOverlay.swift`:

```swift
import AppKit
import Observation
import SwiftUI

final class RecordingOverlayController {
    private static let size = NSSize(width: 280, height: 56)
    private static let bottomMargin: CGFloat = 32

    private let coordinator: DictationCoordinator
    private let panel: NSPanel
    private var observation: Task<Void, Never>?

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: RecordingPill(coordinator: coordinator))
    }

    func start() {
        observation = Task { [weak self, coordinator] in
            for await isVisible in Observations({ coordinator.state.showsOverlay }) {
                self?.setVisible(isVisible)
            }
        }
    }

    private func setVisible(_ isVisible: Bool) {
        guard isVisible, let screen = NSScreen.main?.visibleFrame else {
            return panel.orderOut(nil)
        }
        panel.setFrameOrigin(NSPoint(x: screen.midX - Self.size.width / 2, y: screen.minY + Self.bottomMargin))
        panel.orderFrontRegardless()
    }
}

private struct RecordingPill: View {
    let coordinator: DictationCoordinator

    var body: some View {
        HStack(spacing: 10) { content }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch coordinator.state {
        case .recording(let level):
            Image(systemName: "mic.fill").foregroundStyle(.red)
            LevelMeter(level: level)
        case .transcribing:
            ProgressView().controlSize(.small)
            Text("Transcribing")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).lineLimit(1)
        case .preparing, .idle, .unavailable:
            EmptyView()
        }
    }
}

private struct LevelMeter: View {
    private static let weights: [CGFloat] = [0.4, 0.7, 1, 0.7, 0.4]

    let level: Float

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule().frame(width: 4, height: 4 + 20 * CGFloat(level) * Self.weights[index])
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: Test one suite with `DictationStatePresentationTests`
Expected: 11 test cases pass.

- [ ] **Step 5: Commit**

```bash
git add Features/Dictation VeyraTests
git commit -m "Show dictation status in the menu bar and a floating recording pill

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Composition root and end-to-end verification

**Files:**
- Create: `App/AppDependencies.swift`
- Rewrite: `App/VeyraApp.swift`
- Modify: `README.md` (add a "Using Veyra" section after "Current Status")

**Interfaces:**
- Consumes: every concrete type from Tasks 2–8
- Produces: the running app

- [ ] **Step 1: Implement**

`App/AppDependencies.swift`:

```swift
import AppKit
import Foundation

final class AppDependencies {
    let coordinator: DictationCoordinator
    let permissions: PermissionService
    private let overlay: RecordingOverlayController

    init() {
        let permissions = PermissionService()
        let coordinator = DictationCoordinator(
            audio: AudioRecorder(),
            transcriber: WhisperKitTranscriber(),
            processor: PassthroughTextProcessor(),
            inserter: PasteboardTextInserter(pasteboard: NSPasteboard.general, keystrokes: CGEventKeystrokeSender()),
            hotkey: FnKeyMonitor(),
            permissions: permissions
        )
        self.permissions = permissions
        self.coordinator = coordinator
        overlay = RecordingOverlayController(coordinator: coordinator)

        guard !Self.isRunningTests else { return }
        Task { await launch() }
    }

    private func launch() async {
        overlay.start()
        Task { [permissions] in await permissions.requestInitialAccess() }
        Task { [permissions, coordinator] in await permissions.monitor { coordinator.reconnectHotkey() } }
        await coordinator.start()
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
```

`App/VeyraApp.swift` (replace the whole file):

```swift
import SwiftUI

@main
struct VeyraApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: dependencies.coordinator, permissions: dependencies.permissions)
        } label: {
            Image(systemName: dependencies.coordinator.state.menuBarSymbol)
        }
    }
}
```

`README.md` — insert after the "Current Status" section:

````markdown
# Using Veyra

1. Build and run the `Veyra` scheme. A microphone icon appears in the menu bar.
2. Grant **Microphone** and **Accessibility** access when prompted (or from the menu).
3. Set **System Settings → Keyboard → Press 🌐 key to → Do Nothing** so Fn doesn't open the emoji picker.
4. The first launch downloads the Whisper `large-v3-turbo` model (~1.6 GB) into `~/Library/Application Support/Veyra/Models`. After that Veyra works offline.
5. Hold **Fn**, speak, release. The text is pasted where your cursor is.

If dictation stops working after a rebuild, remove Veyra from **Privacy & Security → Accessibility** and add it again.
````

- [ ] **Step 2: Run the whole suite**

Run the Test-all command.
Expected: every suite passes, `TEST SUCCEEDED`, and no permission prompt or model download starts during the test run.

- [ ] **Step 3: Manual end-to-end check** (owner runs the app from Xcode)

- [ ] Menu shows "Downloading speech model… N%", then "Loading speech model…", then "Hold Fn to dictate".
- [ ] Grant rows disappear from the menu within ~2 s of granting each permission, without relaunching.
- [ ] Hold Fn in Notes, speak a sentence, release: the pill shows the level meter, then "Transcribing", then the text appears at the cursor.
- [ ] Repeat in Slack, VS Code, a browser text field, and Terminal.
- [ ] Copy an image first, dictate, then paste with ⌘V: the image comes back.
- [ ] Tap Fn without speaking: nothing is pasted.
- [ ] Press Fn+← in a text field: the cursor moves, nothing is pasted.
- [ ] Dictate for about 2 minutes: the whole passage is inserted.
- [ ] Quit, turn off Wi-Fi, relaunch: the state reaches "Hold Fn to dictate" without the network.

- [ ] **Step 4: Commit**

```bash
git add App README.md
git commit -m "Wire dictation services into the menu bar app

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
