import AppKit
import OSLog

/// Detecta os atalhos de ditado segurados em qualquer app: ⌥ direito (prompt), ⌘ direito (literal)
/// e toque duplo + segurar no ⌥ direito (revisão do texto selecionado).
final class HotkeyMonitor {
    var onPress: ((DictationMode) -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private var monitors: [Any] = []
    private var logic = HotkeyMonitor.makeLogic()

    /// O intervalo do toque duplo segue a velocidade de clique duplo do sistema, entre 0,5 e 0,8 s.
    private static func makeLogic() -> HotkeyLogic {
        HotkeyLogic(doubleTapWindow: min(max(NSEvent.doubleClickInterval, 0.5), 0.8))
    }

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
        logic = Self.makeLogic()
    }

    private func handle(_ event: NSEvent) {
        let result = switch event.type {
        case .flagsChanged: logic.flagsChanged(keyCode: event.keyCode, flags: event.modifierFlags, time: event.timestamp)
        case .keyDown: logic.keyDown()
        default: HotkeyLogic.Event?.none
        }
        switch result {
        case .press(let mode):
            // Registra o gesto anterior para ajustar os tempos do toque duplo com uso real.
            let previous = logic.previousHold.map {
                "anterior: segurado \($0.duration.formatted(.number.precision(.fractionLength(2)))) s, solto há \($0.gap.formatted(.number.precision(.fractionLength(2)))) s"
            } ?? "sem toque anterior"
            Logger.dictation.notice("Atalho tecla \(event.keyCode, privacy: .public) → \(mode.rawValue, privacy: .public) (\(previous, privacy: .public))")
            onPress?(mode)
        case .release: onRelease?()
        case .cancel: onCancel?()
        case nil: break
        }
    }
}

/// Regras do atalho, separadas dos eventos do AppKit para poderem ser testadas.
///
/// O ditado começa quando só a tecla do atalho está pressionada. Qualquer outra tecla ou modificador
/// enquanto ela está segurada indica um atalho comum (ex.: ⌘C, ⌥E), e o ditado é cancelado.
nonisolated struct HotkeyLogic {
    enum Event: Equatable {
        case press(DictationMode)
        case release
        case cancel
    }

    private struct Trigger {
        let keyCode: UInt16
        let mode: DictationMode
        /// Modo quando a tecla é segurada logo depois de um toque rápido.
        let doubleTapMode: DictationMode?
        let flag: NSEvent.ModifierFlags
        /// Bits dependentes do dispositivo (`NX_DEVICE…KEYMASK`) que distinguem o lado direito do esquerdo.
        let rightSideMask: UInt
        let leftSideMask: UInt
    }

    private static let triggers: [Trigger] = [
        Trigger(keyCode: 61, mode: .prompt, doubleTapMode: .revision, flag: .option, rightSideMask: 0x40, leftSideMask: 0x20),
        Trigger(keyCode: 54, mode: .literal, doubleTapMode: nil, flag: .command, rightSideMask: 0x10, leftSideMask: 0x08),
    ]

    private static let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
    /// Um toque dura no máximo isto…
    static let tapMaxDuration: TimeInterval = 0.4
    /// …e a segunda pressão precisa vir até este tempo depois de soltar.
    let doubleTapWindow: TimeInterval

    private var holding: Trigger?
    private var pressedAt: TimeInterval = 0
    private var interrupted = false
    private var lastTap: (keyCode: UInt16, endedAt: TimeInterval)?
    private var lastRelease: (keyCode: UInt16, duration: TimeInterval, endedAt: TimeInterval)?

    /// Na última pressão: quanto tempo a mesma tecla tinha sido segurada antes e há quanto tempo fora solta.
    private(set) var previousHold: (duration: TimeInterval, gap: TimeInterval)?

    init(doubleTapWindow: TimeInterval = 0.5) {
        self.doubleTapWindow = doubleTapWindow
    }

    mutating func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags, time: TimeInterval) -> Event? {
        if let holding {
            guard keyCode == holding.keyCode else { return interrupt() }
            guard flags.rawValue & holding.rightSideMask == 0 else { return nil }
            self.holding = nil
            let wasTap = !interrupted && time - pressedAt <= Self.tapMaxDuration
            lastTap = wasTap ? (keyCode, time) : nil
            lastRelease = (keyCode, time - pressedAt, time)
            return interrupted ? nil : .release
        }

        guard let trigger = Self.triggers.first(where: { $0.keyCode == keyCode }),
              flags.rawValue & trigger.rightSideMask != 0,
              flags.rawValue & trigger.leftSideMask == 0,
              flags.intersection(Self.modifiers).subtracting(trigger.flag).isEmpty else {
            lastTap = nil
            return nil
        }
        let isDoubleTap = lastTap.map { $0.keyCode == keyCode && time - $0.endedAt <= doubleTapWindow } ?? false
        previousHold = lastRelease.flatMap { $0.keyCode == keyCode ? ($0.duration, time - $0.endedAt) : nil }
        holding = trigger
        pressedAt = time
        interrupted = false
        lastTap = nil
        return .press(isDoubleTap ? trigger.doubleTapMode ?? trigger.mode : trigger.mode)
    }

    mutating func keyDown() -> Event? {
        lastTap = nil
        return holding == nil ? nil : interrupt()
    }

    private mutating func interrupt() -> Event? {
        guard !interrupted else { return nil }
        interrupted = true
        return .cancel
    }
}
