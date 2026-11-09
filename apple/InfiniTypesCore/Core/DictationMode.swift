/// O que o refinamento faz com a fala.
nonisolated enum DictationMode: String, Codable, Sendable {
    /// Reorganiza a fala em um prompt estruturado para a IA de codificação (⌥ direito).
    case prompt
    /// Só limpa: tira vícios e resolve autocorreções, mantendo a ordem e as palavras (⌘ direito).
    case literal
    /// Incorpora a fala ao texto selecionado (toque duplo e segurar o ⌥ direito).
    case revision

    var label: String {
        switch self {
        case .prompt: "Prompt"
        case .literal: "Literal"
        case .revision: "Revisão"
        }
    }

    var systemPromptResource: String {
        switch self {
        case .prompt: "SystemPrompt"
        case .literal: "LiteralPrompt"
        case .revision: "RevisionPrompt"
        }
    }
}
