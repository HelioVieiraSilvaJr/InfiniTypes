import AppKit

/// Detecta o ⌥ direito segurado (push-to-talk) em qualquer app.
///
/// Se outra tecla ou modificador for pressionado enquanto o ⌥ está segurado, era um atalho comum
/// (ex.: ⌥+E para acento), e o ditado é cancelado.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private static let rightOptionKeyCode: UInt16 = 61
    /// Bit do ⌥ direito em `NSEvent.modifierFlags` (`NX_DEVICERALTKEYMASK`).
    private static let rightOptionMask: UInt = 0x40

    private var monitors: [Any] = []
    private var isHolding = false
    private var interrupted = false

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        // O monitor global não recebe eventos quando o próprio app está em foco.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged where event.keyCode == Self.rightOptionKeyCode:
            let rightOptionDown = event.modifierFlags.rawValue & Self.rightOptionMask != 0
            if rightOptionDown, !isHolding {
                let otherModifiers = event.modifierFlags.intersection([.command, .control, .shift, .function])
                guard otherModifiers.isEmpty else { return }
                isHolding = true
                interrupted = false
                onPress?()
            } else if !rightOptionDown, isHolding {
                isHolding = false
                if !interrupted { onRelease?() }
            }
        case .flagsChanged, .keyDown:
            if isHolding, !interrupted {
                interrupted = true
                onCancel?()
            }
        default:
            break
        }
    }
}
