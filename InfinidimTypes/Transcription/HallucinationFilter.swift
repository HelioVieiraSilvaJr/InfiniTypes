import Foundation

/// Remove frases que o Whisper inventa em trechos de silêncio, comuns em português
/// por causa das legendas usadas no treino do modelo.
enum HallucinationFilter {
    /// Frases que, sozinhas, quase sempre são alucinação.
    private static let standalonePhrases: Set<String> = [
        "obrigado", "obrigada", "obrigado por assistir", "tchau", "até a próxima",
        "inscreva-se no canal", "e aí", "música", "legendas pela comunidade amara.org",
    ]

    /// Trechos removidos mesmo no meio de uma fala real.
    private static let embeddedPhrases = [
        "legendas pela comunidade amara.org",
        "legenda adriana zanotto",
    ]

    static func clean(_ text: String) -> String {
        // Marcações de trechos sem fala, como "[Música]" ou "[BLANK_AUDIO]".
        var cleaned = text.replacing(/\[[^\]]*\]/, with: "")
        for phrase in embeddedPhrases {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }
        cleaned = cleaned
            .replacing(/\s{2,}/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalized = cleaned.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if normalized.isEmpty || standalonePhrases.contains(normalized) { return "" }
        return cleaned
    }
}
