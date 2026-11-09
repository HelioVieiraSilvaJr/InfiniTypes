using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace InfiniTypes.Core.Refinement;

/// <summary>Corpo de <c>POST /v1/messages</c>.</summary>
public sealed record MessageRequest(
    [property: JsonPropertyName("model")] string Model,
    [property: JsonPropertyName("max_tokens")] int MaxTokens,
    [property: JsonPropertyName("system")] IReadOnlyList<SystemBlock> System,
    [property: JsonPropertyName("messages")] IReadOnlyList<Message> Messages,
    [property: JsonPropertyName("output_config")] OutputConfig? OutputConfig = null,
    // "default": se o modelo recusar, a API tenta de novo no modelo que a Anthropic recomenda.
    [property: JsonPropertyName("fallbacks")] string? Fallbacks = null);

public sealed record SystemBlock(
    [property: JsonPropertyName("text")] string Text,
    [property: JsonPropertyName("cache_control")] CacheControl? CacheControl = null)
{
    [JsonPropertyName("type")]
    public string Type => "text";
}

public sealed record CacheControl
{
    [JsonPropertyName("type")]
    public string Type => "ephemeral";
}

public sealed record Message(
    [property: JsonPropertyName("role")] string Role,
    [property: JsonPropertyName("content")] string Content);

public sealed record OutputConfig(
    [property: JsonPropertyName("effort")] string? Effort = null,
    // Saída estruturada: a resposta segue o esquema JSON.
    [property: JsonPropertyName("format")] OutputFormat? Format = null);

public sealed record OutputFormat([property: JsonPropertyName("schema")] JsonObject Schema)
{
    [JsonPropertyName("type")]
    public string Type => "json_schema";
}

public sealed record MessageResponse(
    [property: JsonPropertyName("content")] IReadOnlyList<ContentBlock> Content,
    [property: JsonPropertyName("stop_reason")] string? StopReason,
    [property: JsonPropertyName("usage")] Usage? Usage)
{
    /// <summary>Só os blocos de texto; os de raciocínio (<c>thinking</c>) e de fallback ficam de fora.</summary>
    [JsonIgnore]
    public string Text => string.Concat(Content.Where(b => b.Type == "text").Select(b => b.Text));
}

public sealed record ContentBlock(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("text")] string? Text);

public sealed record Usage(
    [property: JsonPropertyName("input_tokens")] int? InputTokens,
    [property: JsonPropertyName("output_tokens")] int? OutputTokens);

public sealed record ModelInfo(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("display_name")] string DisplayName);

public enum AnthropicErrorKind
{
    MissingApiKey,
    Http,
    Refusal,
    Truncated,
    EmptyResponse,
}

public sealed class AnthropicException(AnthropicErrorKind kind, int status = 0, string? type = null, string? apiMessage = null)
    : Exception(Describe(kind, status, apiMessage))
{
    public AnthropicErrorKind Kind { get; } = kind;
    public int Status { get; } = status;
    public string? Type { get; } = type;

    public bool IsRetryable => Kind == AnthropicErrorKind.Http && (Status == 429 || Status >= 500);

    private static string Describe(AnthropicErrorKind kind, int status, string? message) => kind switch
    {
        AnthropicErrorKind.MissingApiKey => "Configure a chave da API nas Preferências",
        AnthropicErrorKind.Refusal => "O modelo recusou o pedido",
        AnthropicErrorKind.Truncated => "A resposta do modelo veio incompleta",
        AnthropicErrorKind.EmptyResponse => "O modelo não devolveu texto",
        _ => status switch
        {
            401 => "Chave da API inválida",
            403 => "A chave não tem permissão para usar este modelo",
            404 => "Modelo indisponível para a sua conta",
            429 => "Limite de uso da API atingido",
            529 => "API da Anthropic sobrecarregada",
            _ => message is null ? $"Erro da API ({status})" : $"Erro da API ({status}): {message}",
        },
    };
}

/// <summary>Cliente HTTP mínimo da API da Anthropic, com o mesmo comportamento dos outros apps.</summary>
public sealed class AnthropicClient(string apiKey, HttpClient? http = null)
{
    public const string BaseUrl = "https://api.anthropic.com/v1";
    public const string ApiVersion = "2026-10-21";
    private const string FallbackBeta = "server-side-fallback-2026-07-01";

    private static readonly HttpClient SharedHttp = new() { Timeout = Timeout.InfiniteTimeSpan };
    private readonly HttpClient _http = http ?? SharedHttp;

    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    /// <summary>Valor do cabeçalho <c>anthropic-beta</c>, quando a requisição usa um recurso em beta.</summary>
    public static string? BetaHeader(MessageRequest body) => body.Fallbacks is null ? null : FallbackBeta;

    public static string Serialize(MessageRequest body) => JsonSerializer.Serialize(body, JsonOptions);

    public Task<MessageResponse> CreateMessageAsync(MessageRequest body, TimeSpan? timeout = null,
        CancellationToken cancellationToken = default) =>
        SendAsync<MessageResponse>(() =>
        {
            var request = MakeRequest(HttpMethod.Post, "messages");
            if (BetaHeader(body) is { } beta) request.Headers.Add("anthropic-beta", beta);
            request.Content = new StringContent(Serialize(body), Encoding.UTF8, "application/json");
            return request;
        }, timeout ?? TimeSpan.FromSeconds(45), retryOnce: true, cancellationToken);

    public async Task<IReadOnlyList<ModelInfo>> ListModelsAsync(CancellationToken cancellationToken = default)
    {
        var models = new List<ModelInfo>();
        string? afterId = null;
        do
        {
            var path = afterId is null ? "models?limit=100" : $"models?limit=100&after_id={Uri.EscapeDataString(afterId)}";
            var page = await SendAsync<ModelPage>(() => MakeRequest(HttpMethod.Get, path), TimeSpan.FromSeconds(30),
                retryOnce: false, cancellationToken);
            models.AddRange(page.Data);
            afterId = page.HasMore ? page.LastId : null;
        } while (afterId is not null);
        return models;
    }

    private HttpRequestMessage MakeRequest(HttpMethod method, string path)
    {
        var request = new HttpRequestMessage(method, $"{BaseUrl}/{path}");
        request.Headers.Add("x-api-key", apiKey);
        request.Headers.Add("anthropic-version", ApiVersion);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        return request;
    }

    private async Task<T> SendAsync<T>(Func<HttpRequestMessage> makeRequest, TimeSpan timeout, bool retryOnce,
        CancellationToken cancellationToken)
    {
        try
        {
            using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutSource.CancelAfter(timeout);
            using var request = makeRequest();
            using var response = await _http.SendAsync(request, timeoutSource.Token);
            var body = await response.Content.ReadAsStringAsync(timeoutSource.Token);
            if (!response.IsSuccessStatusCode)
            {
                var error = TryDeserialize<ErrorEnvelope>(body)?.Error;
                throw new AnthropicException(AnthropicErrorKind.Http, (int)response.StatusCode, error?.Type, error?.Message);
            }
            return JsonSerializer.Deserialize<T>(body, JsonOptions)
                ?? throw new AnthropicException(AnthropicErrorKind.EmptyResponse);
        }
        catch (AnthropicException error) when (retryOnce && error.IsRetryable)
        {
            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
            return await SendAsync<T>(makeRequest, timeout, retryOnce: false, cancellationToken);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new AnthropicException(AnthropicErrorKind.Http, (int)HttpStatusCode.RequestTimeout,
                apiMessage: "tempo esgotado");
        }
    }

    private static T? TryDeserialize<T>(string json)
    {
        try { return JsonSerializer.Deserialize<T>(json, JsonOptions); }
        catch (JsonException) { return default; }
    }

    private sealed record ModelPage(
        [property: JsonPropertyName("data")] IReadOnlyList<ModelInfo> Data,
        [property: JsonPropertyName("has_more")] bool HasMore,
        [property: JsonPropertyName("last_id")] string? LastId);

    private sealed record ErrorEnvelope([property: JsonPropertyName("error")] ErrorDetail? Error);

    private sealed record ErrorDetail(
        [property: JsonPropertyName("type")] string? Type,
        [property: JsonPropertyName("message")] string? Message);
}
