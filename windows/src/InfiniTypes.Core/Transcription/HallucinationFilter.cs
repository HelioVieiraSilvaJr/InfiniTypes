using System.Text.RegularExpressions;

namespace InfiniTypes.Core.Transcription;

/// <summary>
/// Remove frases que o Whisper inventa em trechos de silêncio, comuns em português
/// por causa das legendas usadas no treino do modelo.
/// </summary>
public static partial class HallucinationFilter
{
    /// <summary>Frases que, sozinhas, quase sempre são alucinação.</summary>
    private static readonly HashSet<string> StandalonePhrases =
    [
        "obrigado", "obrigada", "obrigado por assistir", "obrigada por assistir", "muito obrigado",
        "tchau", "tchau tchau", "até a próxima", "até o próximo vídeo", "inscreva-se", "inscreva-se no canal",
        "deixe seu like", "e aí", "música", "legendas pela comunidade amara.org",
        // Mesmo com o idioma fixo em português, às vezes saem as alucinações clássicas em inglês.
        "thank you", "thanks for watching", "you",
    ];

    /// <summary>Créditos de legenda removidos mesmo no meio de uma fala real.</summary>
    private static readonly string[] EmbeddedPhrases =
    [
        "legendas pela comunidade amara.org",
        "subtítulos realizados por la comunidad de amara.org",
        "sous-titres réalisés par la communauté d'amara.org",
        "legenda adriana zanotto",
    ];

    /// <summary>Recebe os nomes das regras aplicadas, nunca o texto ditado.</summary>
    public static Action<string>? Log { get; set; }

    public static string Clean(string text)
    {
        var removed = new List<string>();

        // Marcações de trechos sem fala, como "[Música]" ou "[BLANK_AUDIO]".
        var cleaned = Brackets().Replace(text, "");
        if (cleaned != text) removed.Add("marcação entre colchetes");

        foreach (var phrase in EmbeddedPhrases)
        {
            if (!cleaned.Contains(phrase, StringComparison.InvariantCultureIgnoreCase)) continue;
            cleaned = cleaned.Replace(phrase, "", StringComparison.InvariantCultureIgnoreCase);
            removed.Add("crédito de legenda");
        }
        cleaned = RepeatedSpaces().Replace(cleaned, " ").Trim();

        var normalized = TrimPunctuationAndSpaces(cleaned.ToLowerInvariant());
        if (normalized.Length > 0 && StandalonePhrases.Contains(normalized))
        {
            removed.Add($"frase isolada “{normalized}”");
            cleaned = "";
        }

        if (removed.Count > 0) Log?.Invoke($"Filtro de alucinações: {string.Join(", ", removed)}");
        return normalized.Length == 0 ? "" : cleaned;
    }

    private static string TrimPunctuationAndSpaces(string text)
    {
        static bool Trimmable(char c) => char.IsPunctuation(c) || char.IsWhiteSpace(c);
        var start = 0;
        var end = text.Length;
        while (start < end && Trimmable(text[start])) start++;
        while (end > start && Trimmable(text[end - 1])) end--;
        return text[start..end];
    }

    [GeneratedRegex(@"\[[^\]]*\]")]
    private static partial Regex Brackets();

    [GeneratedRegex(@"\s{2,}")]
    private static partial Regex RepeatedSpaces();
}
