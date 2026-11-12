using System.Text.Json;

namespace InfiniTypes.Core.Refinement;

public sealed record RefinementResult(string Text, string ModelId, int? InputTokens, int? OutputTokens);

/// <param name="EditCount">Quantas alterações foram aplicadas; <c>null</c> quando o modelo reescreveu o texto inteiro.</param>
public sealed record RevisionResult(string Text, string ModelId, int? EditCount, int InputTokens, int OutputTokens);

public enum RevisionFormat
{
    /// <summary>Lista de alterações aplicadas localmente: rápida, e o resto do texto fica intacto.</summary>
    Edits,
    /// <summary>Texto completo reescrito, a reserva quando as alterações não casam com o original.</summary>
    FullText,
}

/// <summary>Transforma a transcrição bruta no texto final usando o modelo escolhido nas preferências.</summary>
public sealed class ClaudeRefiner
{
    private const int MaxTokens = 16_000;

    private readonly Func<string?> _apiKey;
    private readonly Func<(string ModelId, Effort Effort)> _settings;
    private readonly Dictionary<DictationMode, string> _systemPrompts;
    private readonly Dictionary<RevisionFormat, string> _revisionPrompts;

    /// <summary>Recebe os motivos das falhas, nunca o texto do usuário.</summary>
    public Action<string>? Log { get; set; }

    public ClaudeRefiner(Func<string?> apiKey, Func<(string ModelId, Effort Effort)> settings)
    {
        _apiKey = apiKey;
        _settings = settings;
        _systemPrompts = new()
        {
            [DictationMode.Prompt] = Prompts.Load(DictationMode.Prompt.SystemPromptResource()),
            [DictationMode.Literal] = Prompts.Load(DictationMode.Literal.SystemPromptResource()),
        };
        var template = Prompts.Load(DictationMode.Revision.SystemPromptResource());
        _revisionPrompts = new()
        {
            [RevisionFormat.Edits] = RevisionPrompt(template, Prompts.Load("RevisionFormatEdits")),
            [RevisionFormat.FullText] = RevisionPrompt(template, Prompts.Load("RevisionFormatFullText")),
        };
    }

    public async Task<RefinementResult> RefineAsync(string transcript, DictationContext context, DictationMode mode,
        IReadOnlyList<string> vocabulary, CancellationToken cancellationToken = default)
    {
        var (client, model, effort) = Prepare();
        var request = MakeRequest(model, effort, _systemPrompts[mode], transcript, context, vocabulary);
        // Um ditado de 10 minutos rende um prompt longo, e a análise das etapas leva mais tempo.
        var (text, usage) = Text(await client.CreateMessageAsync(request, TimeSpan.FromSeconds(120), cancellationToken));
        return new RefinementResult(text, model.Id, usage?.InputTokens, usage?.OutputTokens);
    }

    /// <summary>Incorpora a fala ao texto selecionado.</summary>
    public async Task<RevisionResult> ReviseAsync(string selection, string dictation, DictationContext context,
        IReadOnlyList<string> vocabulary, CancellationToken cancellationToken = default)
    {
        var (client, model, effort) = Prepare();
        var inputTokens = 0;
        var outputTokens = 0;

        if (model.SupportsEffort)
        {
            var request = MakeRevisionRequest(model, effort, _revisionPrompts[RevisionFormat.Edits], RevisionFormat.Edits,
                selection, dictation, context, vocabulary);
            var (json, usage) = Text(await client.CreateMessageAsync(request, TimeSpan.FromSeconds(60), cancellationToken));
            inputTokens += usage?.InputTokens ?? 0;
            outputTokens += usage?.OutputTokens ?? 0;
            try
            {
                var edits = JsonSerializer.Deserialize<RevisionResponse>(json)?.Edits
                    ?? throw new JsonException("resposta vazia");
                var revised = RevisionPatcher.Apply(edits, selection);
                return new RevisionResult(revised, model.Id, edits.Count, inputTokens, outputTokens);
            }
            catch (Exception error) when (error is RevisionPatchException or JsonException)
            {
                var reason = error is RevisionPatchException ? error.Message : "resposta fora do esquema";
                Log?.Invoke($"Alterações não casaram com o original ({reason}); reescrevendo o texto inteiro");
            }
        }

        var fullText = MakeRevisionRequest(model, effort, _revisionPrompts[RevisionFormat.FullText], RevisionFormat.FullText,
            selection, dictation, context, vocabulary);
        var (text, fullUsage) = Text(await client.CreateMessageAsync(fullText, TimeSpan.FromSeconds(120), cancellationToken));
        // A resposta vem sem espaços nas pontas; mantém os da seleção, como uma quebra de linha final.
        var leading = selection[..(selection.Length - selection.TrimStart().Length)];
        var trailing = selection[selection.TrimEnd().Length..];
        return new RevisionResult(leading + text + trailing, model.Id, null,
            inputTokens + (fullUsage?.InputTokens ?? 0), outputTokens + (fullUsage?.OutputTokens ?? 0));
    }

    // Requisições

    public static MessageRequest MakeRequest(RefinementModel model, Effort effort, string systemPrompt, string transcript,
        DictationContext context, IReadOnlyList<string>? vocabulary = null) =>
        new(
            model.Id,
            // O raciocínio também conta neste limite; o texto final costuma ter poucas centenas de tokens.
            MaxTokens,
            [new SystemBlock(systemPrompt, new CacheControl())],
            [new Message("user", UserMessage(transcript, context, vocabulary ?? []))],
            model.SupportsEffort ? new OutputConfig(effort.RawValue()) : null,
            model.SupportsServerFallback ? "default" : null);

    public static MessageRequest MakeRevisionRequest(RefinementModel model, Effort effort, string systemPrompt,
        RevisionFormat format, string selection, string dictation, DictationContext context,
        IReadOnlyList<string> vocabulary)
    {
        var outputConfig = model.SupportsEffort
            ? new OutputConfig(effort.RawValue(), format == RevisionFormat.Edits ? new OutputFormat(RevisionPatcher.Schema()) : null)
            : null;
        var message = ContextBlock(context, vocabulary)
            + $"\n\n<texto_original>\n{selection}\n</texto_original>\n\n<fala>\n{dictation}\n</fala>";
        return new MessageRequest(
            model.Id,
            MaxTokens,
            [new SystemBlock(systemPrompt, new CacheControl())],
            [new Message("user", message)],
            outputConfig,
            model.SupportsServerFallback ? "default" : null);
    }

    public static string UserMessage(string transcript, DictationContext context, IReadOnlyList<string> vocabulary) =>
        ContextBlock(context, vocabulary) + $"\n\n<transcricao>\n{transcript}\n</transcricao>";

    /// <summary><c>{{formato}}</c> no prompt da revisão vira as instruções do formato pedido.</summary>
    public static string RevisionPrompt(string template, string instructions) =>
        template.Replace("{{formato}}", instructions.Trim());

    private static string ContextBlock(DictationContext context, IReadOnlyList<string> vocabulary)
    {
        var lines = new List<string>();
        if (context.AppName is { } app) lines.Add($"App: {app}");
        if (context.WindowTitle is { } title) lines.Add($"Janela: {title}");
        if (context.ProjectName is { } project) lines.Add($"Projeto: {project}");
        var block = $"<contexto>\n{(lines.Count == 0 ? "(desconhecido)" : string.Join("\n", lines))}\n</contexto>";
        if (vocabulary.Count > 0) block += $"\n\n<glossario>\n{string.Join("\n", vocabulary)}\n</glossario>";
        return block;
    }

    // Respostas

    private (AnthropicClient Client, RefinementModel Model, Effort Effort) Prepare()
    {
        var apiKey = _apiKey();
        if (string.IsNullOrWhiteSpace(apiKey)) throw new AnthropicException(AnthropicErrorKind.MissingApiKey);
        var (modelId, effort) = _settings();
        return (new AnthropicClient(apiKey), ModelCatalog.Model(modelId), effort);
    }

    private static (string Text, Usage? Usage) Text(MessageResponse response)
    {
        switch (response.StopReason)
        {
            case "refusal": throw new AnthropicException(AnthropicErrorKind.Refusal);
            case "max_tokens": throw new AnthropicException(AnthropicErrorKind.Truncated);
        }
        var text = response.Text.Trim();
        if (text.Length == 0) throw new AnthropicException(AnthropicErrorKind.EmptyResponse);
        return (text, response.Usage);
    }
}
