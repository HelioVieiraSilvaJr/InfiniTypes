using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace InfiniTypes.Core.Storage;

/// <summary>Um ditado real marcado no histórico, no formato do conjunto de avaliação do refinador.</summary>
public sealed record EvalCase(
    // Data e hora do ditado (ISO 8601).
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("mode")] string Mode,
    [property: JsonPropertyName("app")] string? App,
    [property: JsonPropertyName("window_title")] string? WindowTitle,
    [property: JsonPropertyName("project")] string? Project,
    [property: JsonPropertyName("raw_transcript")] string RawTranscript,
    // Na revisão, o texto que estava selecionado.
    [property: JsonPropertyName("original_text")] string? OriginalText,
    // O que o app entregou na época, para comparar com versões novas do prompt.
    [property: JsonPropertyName("delivered_text")] string DeliveredText,
    [property: JsonPropertyName("model_id")] string? ModelId,
    [property: JsonPropertyName("refined")] bool Refined);

/// <summary>Exporta os ditados marcados para <c>Eval\cases.jsonl</c>, no mesmo formato do Mac.</summary>
public static class EvalExporter
{
    private static readonly JsonSerializerOptions Options = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static EvalCase FromRecord(DictationRecord record) => new(
        record.CreatedAt.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"), record.Mode.RawValue(), record.AppName,
        record.WindowTitle, record.ProjectName, record.RawTranscript, record.OriginalText, record.Text,
        record.ModelId, record.Refined);

    /// <summary>Uma linha JSON por caso, do mais antigo para o mais novo.</summary>
    public static string Jsonl(IEnumerable<EvalCase> cases) =>
        string.Concat(cases.OrderBy(c => c.Id, StringComparer.Ordinal)
            .Select(c => JsonSerializer.Serialize(c, Options) + "\n"));

    public static string Export(IEnumerable<DictationRecord> records, string folder)
    {
        var path = Path.Combine(folder, "Eval", "cases.jsonl");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, Jsonl(records.Select(FromRecord)));
        return path;
    }
}
