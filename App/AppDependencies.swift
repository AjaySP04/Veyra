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
            processor: OllamaTextProcessor(client: OllamaClient()),
            inserter: PasteboardTextInserter(pasteboard: NSPasteboard.general, keystrokes: CGEventKeystrokeSender()),
            hotkey: FnKeyMonitor(),
            permissions: permissions,
            contextProvider: FrontmostAppContextProvider()
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
