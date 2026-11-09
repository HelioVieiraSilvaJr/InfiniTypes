using System.Globalization;
using System.Text.Json.Serialization;

namespace InfiniTypes.Core.Storage;

/// <summary>Termos com a grafia correta, que ajudam o Whisper a reconhecer e o Claude a corrigir.</summary>
public sealed class Glossary
{
    /// <summary>Um termo por linha. Guardado como texto para a edição livre nas preferências.</summary>
    [JsonPropertyName("global_terms")]
    public string GlobalTerms { get; set; } = "";

    [JsonPropertyName("projects")]
    public List<GlossaryProject> Projects { get; set; } = [];

    /// <summary>Termos globais mais os do projeto cujo nome aparece no título da janela.</summary>
    public GlossaryMatch Match(string? windowTitle)
    {
        var project = windowTitle is null
            ? null
            : Projects
                .Where(p => p.Name.Trim().Length > 0)
                // O nome mais longo vence, para "api-admin" não ser confundido com "api".
                .OrderByDescending(p => p.Name.Trim().Length)
                .FirstOrDefault(p => Contains(windowTitle, p.Name.Trim()));
        var seen = new HashSet<string>();
        var terms = Lines(GlobalTerms).Concat(Lines(project?.Terms ?? ""))
            .Where(term => seen.Add(term.ToLowerInvariant()))
            .ToList();
        return new GlossaryMatch(project?.Name.Trim(), terms);
    }

    public static IReadOnlyList<string> Lines(string text) =>
        text.Split(['\r', '\n'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);

    private static bool Contains(string title, string name) =>
        CultureInfo.InvariantCulture.CompareInfo.IndexOf(title, name,
            CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace) >= 0;
}

public sealed class GlossaryProject
{
    /// <summary>Reconhecido quando aparece no título da janela.</summary>
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("terms")]
    public string Terms { get; set; } = "";
}

public sealed record GlossaryMatch(string? ProjectName, IReadOnlyList<string> Terms);
