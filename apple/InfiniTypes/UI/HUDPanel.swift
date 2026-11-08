import AppKit
import Observation
import SwiftUI

enum HUDState: Equatable {
    case hidden
    case recording(String)
    case working(String)
    case success(String)
    case notice(String)
    case failure(String)
}

@Observable
final class HUDModel {
    var state: HUDState = .hidden
    var level: Float = 0
}

/// Aviso flutuante na parte de baixo da tela. Não rouba o foco nem recebe cliques.
final class HUDController {
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?

    private static let size = NSSize(width: 560, height: 64)

    /// `level` é consultado ~30 vezes por segundo enquanto o estado estiver visível.
    func show(_ state: HUDState, level: (() -> Float)? = nil) {
        hideTask?.cancel()
        levelTask?.cancel()
        model.state = state
        model.level = 0
        if let level {
            levelTask = Task { [model] in
                while !Task.isCancelled {
                    model.level = level()
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
        }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()

        switch state {
        case .success, .notice: scheduleHide(after: .seconds(2))
        case .failure: scheduleHide(after: .seconds(6))
        case .hidden: hide()
        case .recording, .working: break
        }
    }

    func hide() {
        hideTask?.cancel()
        levelTask?.cancel()
        panel?.orderOut(nil)
        model.state = .hidden
    }

    private func scheduleHide(after delay: Duration) {
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 64))
    }
}

private struct HUDView: View {
    let model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
            symbol
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            if case .recording = model.state {
                LevelMeter(level: model.level)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var symbol: some View {
        switch model.state {
        case .recording:
            Image(systemName: "mic.fill").foregroundStyle(.red)
        case .working:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .notice:
            Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.blue)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .hidden:
            EmptyView()
        }
    }

    private var message: String {
        switch model.state {
        case .recording(let text), .working(let text), .success(let text), .notice(let text), .failure(let text): text
        case .hidden: ""
        }
    }
}

private struct LevelMeter: View {
    let level: Float
    private let weights: [Float] = [0.5, 0.8, 1, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(.red.opacity(0.85))
                    .frame(width: 3, height: CGFloat(4 + 14 * min(1, level * weights[index])))
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: level)
    }
}
