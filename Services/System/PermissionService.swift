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
