import AppKit
import ApplicationServices
import Carbon.HIToolbox
import OSLog

/// Lê o texto selecionado no app em foco, para a revisão por voz.
enum SelectionReader {
    enum Result: Equatable {
        case text(String)
        /// Campo de senha: o conteúdo nunca é lido.
        case secureField
        case none
    }

    /// Pela Accessibility, sem tocar na área de transferência. Funciona em apps nativos e campos web;
    /// apps Electron (VS Code, Cursor) e documentos como o do Pages costumam não expor a seleção.
    static func accessibilitySelection() -> Result {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .none }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = AX.element(appElement, kAXFocusedUIElementAttribute) else { return .none }
        if AX.string(focused, kAXRoleAttribute) == "AXSecureTextField"
            || AX.string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
            return .secureField
        }
        guard let text = AX.string(focused, kAXSelectedTextAttribute), !text.isEmpty else { return .none }
        return .text(text)
    }

    /// Simula ⌘C e lê o que foi copiado, restaurando a área de transferência em seguida.
    ///
    /// Só dispara com todos os modificadores soltos: com o ⌥ ainda pressionado, o ⌘C viraria outro
    /// atalho (no Pages, ⌥⌘C é "Copiar Estilo"). Sem seleção, nada é copiado e a função espera até
    /// `timeout`: o Pages, que gera texto formatado, pode levar quase um segundo para copiar.
    static func copySelection(timeout: Duration) async -> Result {
        for _ in 0..<10 where modifiersHeld {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard !modifiersHeld else {
            Logger.dictation.notice("Seleção por ⌘C: modificadores ainda pressionados, nada foi copiado")
            return .none
        }
        guard !IsSecureEventInputEnabled() else {
            Logger.dictation.notice("Seleção por ⌘C: entrada segura ativa (campo de senha), nada foi copiado")
            return .none
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        let start = ContinuousClock.now
        TextInserter.postShortcut(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        var copied: String?
        while ContinuousClock.now - start < timeout {
            try? await Task.sleep(for: .milliseconds(25))
            if pasteboard.changeCount != before {
                copied = pasteboard.string(forType: .string)
                break
            }
        }
        let elapsed = Int((ContinuousClock.now - start) / .milliseconds(1))
        if pasteboard.changeCount != before {
            snapshot.restore(to: pasteboard)
            Logger.dictation.notice("Seleção por ⌘C: copiada em \(elapsed, privacy: .public) ms (\(copied?.count ?? 0, privacy: .public) caracteres)")
        } else {
            Logger.dictation.notice("Seleção por ⌘C: nada copiado em \(elapsed, privacy: .public) ms")
        }
        guard let copied, !copied.isEmpty else { return .none }
        return .text(copied)
    }

    private static var modifiersHeld: Bool {
        !CGEventSource.flagsState(.hidSystemState)
            .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            .isEmpty
    }
}
