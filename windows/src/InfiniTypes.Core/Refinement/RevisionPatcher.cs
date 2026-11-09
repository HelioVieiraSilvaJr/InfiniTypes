using System.Text;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace InfiniTypes.Core.Refinement;

/// <summary>Uma alteração devolvida pelo modelo na revisão.</summary>
/// <param name="Original">Trecho copiado literalmente do texto original.</param>
/// <param name="Revised">O que fica no lugar do trecho.</param>
public sealed record RevisionEdit(
    [property: JsonPropertyName("original")] string Original,
    [property: JsonPropertyName("revised")] string Revised);

public sealed record RevisionResponse([property: JsonPropertyName("edits")] IReadOnlyList<RevisionEdit> Edits);

public enum RevisionPatchError
{
    NotFound,
    Ambiguous,
    Overlapping,
}

public sealed class RevisionPatchException(RevisionPatchError error) : Exception(Describe(error))
{
    public RevisionPatchError Error { get; } = error;

    /// <summary>Motivo para o log, sem o trecho do texto do usuário.</summary>
    private static string Describe(RevisionPatchError error) => error switch
    {
        RevisionPatchError.NotFound => "trecho não encontrado",
        RevisionPatchError.Ambiguous => "trecho repetido",
        _ => "alterações sobrepostas",
    };
}

/// <summary>Aplica ao texto original as alterações devolvidas pelo modelo. O que não foi alterado fica idêntico.</summary>
public static class RevisionPatcher
{
    /// <summary>Esquema JSON enviado à API para a resposta vir como <see cref="RevisionResponse"/>.</summary>
    public static JsonObject Schema() => new()
    {
        ["type"] = "object",
        ["properties"] = new JsonObject
        {
            ["edits"] = new JsonObject
            {
                ["type"] = "array",
                ["items"] = new JsonObject
                {
                    ["type"] = "object",
                    ["properties"] = new JsonObject
                    {
                        ["original"] = new JsonObject { ["type"] = "string" },
                        ["revised"] = new JsonObject { ["type"] = "string" },
                    },
                    ["required"] = new JsonArray("original", "revised"),
                    ["additionalProperties"] = false,
                },
            },
        },
        ["required"] = new JsonArray("edits"),
        ["additionalProperties"] = false,
    };

    /// <summary>Cada trecho precisa aparecer uma única vez no original, e os trechos não podem se sobrepor.</summary>
    public static string Apply(IReadOnlyList<RevisionEdit> edits, string text)
    {
        var located = new List<(int Start, int Length, string Revised)>();
        foreach (var edit in edits)
        {
            if (edit.Original.Length == 0) throw new RevisionPatchException(RevisionPatchError.NotFound);
            var start = text.IndexOf(edit.Original, StringComparison.Ordinal);
            if (start < 0) throw new RevisionPatchException(RevisionPatchError.NotFound);
            if (text.IndexOf(edit.Original, start + edit.Original.Length, StringComparison.Ordinal) >= 0)
                throw new RevisionPatchException(RevisionPatchError.Ambiguous);
            located.Add((start, edit.Original.Length, edit.Revised));
        }
        located.Sort((a, b) => a.Start.CompareTo(b.Start));

        var result = new StringBuilder();
        var cursor = 0;
        foreach (var edit in located)
        {
            if (edit.Start < cursor) throw new RevisionPatchException(RevisionPatchError.Overlapping);
            result.Append(text, cursor, edit.Start - cursor).Append(edit.Revised);
            cursor = edit.Start + edit.Length;
        }
        return result.Append(text, cursor, text.Length - cursor).ToString();
    }
}
