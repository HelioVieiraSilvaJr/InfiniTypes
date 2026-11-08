import Foundation
import OSLog

/// Remove frases que o Whisper inventa em trechos de silêncio, comuns em português
/// por causa das legendas usadas no treino do modelo.
enum HallucinationFilter {
    /// Frases que, sozinhas, quase sempre são alucinação.
    private static let standalonePhrases: Set<String> = [
        "obrigado", "obrigada", "obrigado por assistir", "obrigada por assistir", "muito obrigado",
        "tchau", "tchau tchau", "até a próxima", "até o próximo vídeo", "inscreva-se", "inscreva-se no canal",
        "deixe seu like", "e aí", "música", "legendas pela comunidade amara.org",
        // Mesmo com o idioma fixo em português, às vezes saem as alucinações clássicas em inglês.
        "thank you", "thanks for watching", "you",
    ]

    /// Créditos de legenda removidos mesmo no meio de uma fala real.
    private static let embeddedPhrases = [
        "legendas pela comunidade amara.org",
        "subtítulos realizados por la comunidad de amara.org",
        "sous-titres réalisés par la communauté d'amara.org",
        "legenda adriana zanotto",
    ]

    static func clean(_ text: String) -> String {
        var removed: [String] = []

        // Marcações de trechos sem fala, como "[Música]" ou "[BLANK_AUDIO]".
        var cleaned = text.replacing(/\[[^\]]*\]/, with: "")
        if cleaned != text { removed.append("marcação entre colchetes") }

        for phrase in embeddedPhrases where cleaned.range(of: phrase, options: .caseInsensitive) != nil {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
            removed.append("crédito de legenda")
        }
        cleaned = cleaned
            .replacing(/\s{2,}/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalized = cleaned.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if !normalized.isEmpty, standalonePhrases.contains(normalized) {
            removed.append("frase isolada “\(normalized)”")
            cleaned = ""
        }

        // Só os nomes das regras vão para o log, nunca o texto ditado.
        if !removed.isEmpty {
            Logger.transcription.notice("Filtro de alucinações: \(removed.joined(separator: ", "), privacy: .public)")
        }
        return normalized.isEmpty ? "" : cleaned
    }
}
