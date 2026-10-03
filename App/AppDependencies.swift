import AppKit
import Foundation

final class AppDependencies {
    let coordinator: DictationCoordinator
    let permissions: PermissionService
    let iconAnimator = MenuBarIconAnimator()
    private let overlay: RecordingOverlayController

    init() {
        let permissions = PermissionService()
        let keystrokes = CGEventKeystrokeSender()
        let client = OllamaClient()
        let openTool = OpenTool(
            apps: InstalledAppDirectory(),
            files: SpotlightFileSearcher(),
            workspace: NSWorkspaceOpener(),
            home: FileManager.default.homeDirectoryForCurrentUser
        )
        let inserter = PasteboardTextInserter(pasteboard: NSPasteboard.general, keystrokes: keystrokes)
        let frontmostApp = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        let rewriteTool = RewriteTool(
            selection: AXSelectionReader(),
            copier: ClipboardCopier(pasteboard: NSPasteboard.general, keystrokes: keystrokes),
            rewriter: OllamaTextRewriter(client: client),
            inserter: inserter,
            keystrokes: keystrokes,
            frontmostApp: frontmostApp
        )
        let shellTool = ShellTool(inserter: inserter, keystrokes: keystrokes, frontmostApp: frontmostApp)
        let sendTool = SendTool(inserter: inserter, keystrokes: keystrokes, frontmostApp: frontmostApp)
        let coordinator = DictationCoordinator(
            audio: AudioRecorder(),
            transcriber: WhisperKitTranscriber(),
            processor: OllamaTextProcessor(client: client),
            inserter: inserter,
            keystrokes: keystrokes,
            hotkey: FnKeyMonitor(),
            permissions: permissions,
            contextProvider: FrontmostAppContextProvider(),
            agent: AgentRunner(caller: client, registry: ToolRegistry([openTool, rewriteTool, shellTool, sendTool]))
        )
        self.permissions = permissions
        self.coordinator = coordinator
        overlay = RecordingOverlayController(coordinator: coordinator)

        guard !Self.isRunningTests else { return }
        Task { await launch() }
    }

    private func launch() async {
        overlay.start()
        Task { [coordinator, iconAnimator] in
            for await icon in Observations({ coordinator.state.menuBarIcon }) {
                iconAnimator.update(swinging: icon == .mark(swinging: true))
            }
        }
        Task { [permissions] in await permissions.requestInitialAccess() }
        Task { [permissions, coordinator] in await permissions.monitor { coordinator.reconnectHotkey() } }
        await coordinator.start()
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
