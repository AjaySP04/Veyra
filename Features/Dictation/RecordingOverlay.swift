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
