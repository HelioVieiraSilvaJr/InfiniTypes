using System.Globalization;

namespace InfiniTypes.Core.Refinement;

/// <summary>Quanto o modelo raciocina antes de responder (<c>output_config.effort</c>).</summary>
public enum Effort
{
    Low,
    Medium,
    High,
}

public static class EffortExtensions
{
    public static string RawValue(this Effort effort) => effort switch
    {
        Effort.Medium => "medium",
        Effort.High => "high",
        _ => "low",
    };

    public static Effort ParseEffort(string? raw) => raw switch
    {
        "medium" => Effort.Medium,
        "high" => Effort.High,
        _ => Effort.Low,
    };

    public static string Label(this Effort effort) => effort switch
    {
        Effort.Medium => "Média",
        Effort.High => "Alta",
        _ => "Baixa",
    };
}

/// <summary>Modelo da Anthropic que pode fazer o refinamento.</summary>
/// <param name="Pricing">Preço em US$ por milhão de tokens; <c>null</c> para modelos que o app não conhece.</param>
/// <param name="SupportsEffort">Aceita <c>output_config.effort</c>. Modelos desconhecidos recebem a requisição mínima, sem ele.</param>
/// <param name="SupportsServerFallback">Aceita <c>fallbacks: "default"</c> (nova tentativa do lado do servidor quando o modelo recusa).</param>
public sealed record RefinementModel(
    string Id,
    string DisplayName,
    ModelPricing? Pricing,
    bool SupportsEffort,
    bool SupportsServerFallback)
{
    public string? PriceLabel => Pricing is null
        ? null
        : $"US$ {Format(Pricing.Input)} / {Format(Pricing.Output)} por milhão de tokens";

    /// <summary>"4", "0,10": centavos só quando o preço não é inteiro.</summary>
    private static string Format(double price) =>
        price.ToString(Math.Round(price) == price ? "0" : "0.00", CultureInfo.GetCultureInfo("pt-BR"));

    public override string ToString() => DisplayName;
}

public sealed record ModelPricing(double Input, double Output);

public static class ModelCatalog
{
    public const string DefaultModelId = "claude-opus-5-5";

    /// <summary>Modelos atuais da Anthropic, para os quais o app monta a requisição completa.</summary>
    public static readonly IReadOnlyList<RefinementModel> Known =
    [
        new("claude-opus-5-5", "Claude Opus 5.5", new(4, 20), SupportsEffort: true, SupportsServerFallback: true),
        new("claude-sonnet-5-5", "Claude Sonnet 5.5", new(2, 10), SupportsEffort: true, SupportsServerFallback: true),
        new("claude-haiku-5-5", "Claude Haiku 5.5", new(0.10, 0.50), SupportsEffort: true, SupportsServerFallback: false),
        new("claude-fable-5-1", "Claude Fable 5.1", new(10, 50), SupportsEffort: true, SupportsServerFallback: true),
    ];

    public static RefinementModel Model(string id) =>
        Known.FirstOrDefault(m => m.Id == id) ?? Unknown(id, id);

    /// <summary>Modelos conhecidos primeiro, seguidos dos demais que a Models API devolveu para a conta.</summary>
    public static IReadOnlyList<RefinementModel> Merge(IEnumerable<ModelInfo> available)
    {
        var knownIds = Known.Select(m => m.Id).ToHashSet();
        return [.. Known, .. available.Where(m => !knownIds.Contains(m.Id)).Select(m => Unknown(m.Id, m.DisplayName))];
    }

    private static RefinementModel Unknown(string id, string displayName) =>
        new(id, displayName, null, SupportsEffort: false, SupportsServerFallback: false);
}
