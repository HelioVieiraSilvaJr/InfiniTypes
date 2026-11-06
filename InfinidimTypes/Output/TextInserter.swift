import AppKit
import Carbon.HIToolbox

/// Cola texto no campo em foco via área de transferência + ⌘V simulado, preservando o que você tinha copiado.
enum TextInserter {
    /// Gerenciadores de área de transferência ignoram itens com este tipo.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        pasteboard.writeObjects([item])
        let ourChangeCount = pasteboard.changeCount

        postCommandV()

        // Dá tempo para o app de destino ler a área de transferência antes de restaurá-la.
        try? await Task.sleep(for: .milliseconds(350))
        if pasteboard.changeCount == ourChangeCount {
            snapshot.restore(to: pasteboard)
        }
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Só cola: nunca envia Enter.
    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Cópia de todos os itens e tipos da área de transferência.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                data[type] = item.data(forType: type)
            }
            return data
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { data in
            let item = NSPasteboardItem()
            for (type, value) in data {
                item.setData(value, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
