namespace InfiniTypes.Core;

/// <summary>O que o refinamento faz com a fala.</summary>
public enum DictationMode
{
    /// <summary>Reorganiza a fala em um prompt estruturado para a IA de codificação.</summary>
    Prompt,
    /// <summary>Só limpa: tira vícios e resolve autocorreções, mantendo a ordem e as palavras.</summary>
    Literal,
    /// <summary>Incorpora a fala ao texto selecionado.</summary>
    Revision,
}

public static class DictationModeExtensions
{
    /// <summary>Nome gravado no histórico e na exportação da avaliação, igual ao das outras plataformas.</summary>
    public static string RawValue(this DictationMode mode) => mode switch
    {
        DictationMode.Literal => "literal",
        DictationMode.Revision => "revision",
        _ => "prompt",
    };

    public static DictationMode ParseMode(string? raw) => raw switch
    {
        "literal" => DictationMode.Literal,
        "revision" => DictationMode.Revision,
        _ => DictationMode.Prompt,
    };

    public static string Label(this DictationMode mode) => mode switch
    {
        DictationMode.Literal => "Literal",
        DictationMode.Revision => "Revisão",
        _ => "Prompt",
    };

    public static string SystemPromptResource(this DictationMode mode) => mode switch
    {
        DictationMode.Literal => "LiteralPrompt",
        DictationMode.Revision => "RevisionPrompt",
        _ => "SystemPrompt",
    };
}

/// <summary>Onde o ditado aconteceu: app e janela em foco e, quando reconhecido, o projeto do glossário.</summary>
public sealed record DictationContext(
    string? AppName = null,
    string? AppId = null,
    string? WindowTitle = null,
    string? ProjectName = null)
{
    public static readonly DictationContext Empty = new();
}
