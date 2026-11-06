import AppKit
import SwiftUI

/// Abre as janelas do app (que não tem ícone no Dock) e as traz para a frente.
final class WindowPresenter: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]
    private var closeHandlers: [String: () -> Void] = [:]

    /// `defaultSize` torna a janela redimensionável; sem ele, a janela assume o tamanho do conteúdo.
    func show(id: String, title: String, defaultSize: NSSize? = nil,
              onClose: (() -> Void)? = nil, @ViewBuilder content: () -> some View) {
        if let window = windows[id] {
            bringToFront(window)
            return
        }

        let controller = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let defaultSize {
            controller.sizingOptions = [.minSize]
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(defaultSize)
        } else {
            window.styleMask = [.titled, .closable]
        }
        window.center()

        windows[id] = window
        closeHandlers[id] = onClose
        bringToFront(window)
    }

    func close(id: String) {
        windows[id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = window.identifier?.rawValue else { return }
        closeHandlers.removeValue(forKey: id)?()
        windows[id] = nil
    }

    private func bringToFront(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
