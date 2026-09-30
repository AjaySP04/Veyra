import AppKit
import AVFoundation
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
        Button("Microphone Mode…") { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }
        Button("Quit Veyra") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
