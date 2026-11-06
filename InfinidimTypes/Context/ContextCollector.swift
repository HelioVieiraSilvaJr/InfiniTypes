import AppKit
import ApplicationServices

/// Onde o ditado aconteceu: app em foco e título da janela.
nonisolated struct DictationContext: Sendable, Equatable {
    var appName: String?
    var bundleID: String?
    var windowTitle: String?

    static let empty = DictationContext()
}

enum ContextCollector {
    static func capture() -> DictationContext {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .empty }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let window = AX.element(appElement, kAXFocusedWindowAttribute)
        let title = window.flatMap { AX.string($0, kAXTitleAttribute) }
        return DictationContext(
            appName: app.localizedName,
            bundleID: app.bundleIdentifier,
            windowTitle: title?.isEmpty == false ? title : nil
        )
    }
}

/// Leitura de atributos da Accessibility API.
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> (CFTypeRef?, AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value, error)
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        let (value, error) = value(element, attribute)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        let (value, error) = value(element, attribute)
        guard error == .success else { return nil }
        return value as? String
    }

    static func hasAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        value(element, attribute).1 == .success
    }
}
