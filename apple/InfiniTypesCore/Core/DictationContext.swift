import Foundation

/// Onde o ditado aconteceu: app em foco, título da janela e, se o glossário reconhecer, o projeto.
nonisolated struct DictationContext: Sendable, Equatable {
    var appName: String?
    var bundleID: String?
    var windowTitle: String?
    var projectName: String?

    static let empty = DictationContext()
}
