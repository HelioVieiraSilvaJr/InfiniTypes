import AppKit
import ApplicationServices
import OSLog

enum FocusResult: String {
    case editable
    case notEditable
    /// A Accessibility não respondeu; na dúvida, o texto é colado (ele já está salvo no histórico).
    case unknown
}

/// Decide se há um campo de texto em foco para receber o ⌘V.
enum FocusDetector {
    /// Terminais e editores sempre têm onde colar, mesmo quando a Accessibility responde mal
    /// (apps Electron e terminais expõem o foco de forma irregular).
    static let alwaysEditableBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
        "com.apple.dt.Xcode",
        "dev.zed.Zed",
        "com.jetbrains.intellij",
        "com.jetbrains.WebStorm",
        "com.jetbrains.pycharm",
    ]

    static let editableRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    static func check() -> FocusResult {
        let app = NSWorkspace.shared.frontmostApplication
        let (result, detail) = evaluate(app)
        Logger.dictation.notice(
            "Foco: \(app?.bundleIdentifier ?? "nenhum app", privacy: .public) (\(detail, privacy: .public)) → \(result.rawValue, privacy: .public)"
        )
        return result
    }

    private static func evaluate(_ app: NSRunningApplication?) -> (FocusResult, String) {
        guard let app else { return (.unknown, "sem app em foco") }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return (.notEditable, "o próprio app") }
        if let bundleID = app.bundleIdentifier, alwaysEditableBundleIDs.contains(bundleID) { return (.editable, "app conhecido") }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let (focused, error) = AX.value(appElement, kAXFocusedUIElementAttribute)
        switch error {
        case .success:
            break
        case .noValue:
            return (.notEditable, "nenhum elemento em foco")
        default:
            return (.unknown, "AXError \(error.rawValue)")
        }
        guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return (.unknown, "foco sem elemento") }
        let element = focused as! AXUIElement
        let role = AX.string(element, kAXRoleAttribute)
        let hasTextSelection = AX.hasAttribute(element, kAXSelectedTextRangeAttribute)
        let detail = "papel \(role ?? "nenhum"), seleção de texto: \(hasTextSelection ? "sim" : "não")"
        return (classify(role: role, hasTextSelection: hasTextSelection, bundleID: app.bundleIdentifier), detail)
    }

    /// Campos de texto têm papel de texto ou expõem uma seleção de texto (ex.: `contenteditable` em páginas web).
    /// Fora isso, só descarta a colagem quando é claro que não há onde digitar, como na área de trabalho do
    /// Finder: apps que desenham o próprio documento, como o Pages, informam o foco como uma área de rolagem.
    static func classify(role: String?, hasTextSelection: Bool, bundleID: String?) -> FocusResult {
        if let role, editableRoles.contains(role) { return .editable }
        if hasTextSelection { return .editable }
        if bundleID == "com.apple.finder" { return .notEditable }
        return .unknown
    }
}
