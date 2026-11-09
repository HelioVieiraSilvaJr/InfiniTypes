using System.Text;
using InfiniTypes.Core.Transcription;
using Whisper.net;

namespace InfiniTypes.App.Services;

/// <summary>
/// Transcrição local com o whisper.cpp (Whisper.net) e o large-v3-turbo quantizado. Usa a GPU pelo Vulkan
/// quando há driver, e a CPU como reserva.
/// </summary>
internal sealed class WhisperTranscriber : ITranscriber, IDisposable
{
    private const string ModelFile = "ggml-large-v3-turbo-q5_0.bin";
    private const string ModelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + ModelFile;

    private readonly SemaphoreSlim _loadGate = new(1, 1);
    private WhisperFactory? _factory;

    /// <summary>Progresso do download do modelo, de 0 a 1, ou <c>null</c> quando não está baixando.</summary>
    public double? DownloadProgress { get; private set; }

    public bool IsReady => _factory is not null;

    /// <summary>Baixa (na primeira vez, ~550 MB) e carrega o modelo, sem esperar o primeiro ditado.</summary>
    public Task PrepareAsync() => LoadAsync(CancellationToken.None);

    public async Task<string> TranscribeAsync(float[] samples, IReadOnlyList<string> vocabulary,
        CancellationToken cancellationToken = default)
    {
        var factory = await LoadAsync(cancellationToken);
        return await Task.Run(async () =>
        {
            var builder = factory.CreateBuilder()
                // Fixo em português: a detecção automática tende a trocar para inglês com muitos termos técnicos.
                .WithLanguage("pt")
                .WithTemperature(0);
            // O glossário vira o "texto anterior" do Whisper, o que puxa o reconhecimento para essas grafias.
            if (vocabulary.Count > 0) builder = builder.WithPrompt(" " + string.Join(", ", vocabulary.Take(60)) + ".");
            await using var processor = builder.Build();
            var text = new StringBuilder();
            await foreach (var segment in processor.ProcessAsync(samples, cancellationToken))
                text.Append(segment.Text);
            return text.ToString().Trim();
        }, cancellationToken);
    }

    public void Dispose() => _factory?.Dispose();

    private async Task<WhisperFactory> LoadAsync(CancellationToken cancellationToken)
    {
        if (_factory is { } ready) return ready;
        await _loadGate.WaitAsync(cancellationToken);
        try
        {
            if (_factory is { } loaded) return loaded;
            var path = Path.Combine(AppPaths.Models, ModelFile);
            if (!File.Exists(path)) await DownloadAsync(path, cancellationToken);
            _factory = await Task.Run(() => WhisperFactory.FromPath(path), cancellationToken);
            Log.Info("Modelo de voz carregado");
            return _factory;
        }
        finally
        {
            _loadGate.Release();
        }
    }

    private async Task DownloadAsync(string path, CancellationToken cancellationToken)
    {
        Log.Info("Baixando o modelo de voz");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var partial = path + ".partial";
        using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        using var response = await http.GetAsync(ModelUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength;
        DownloadProgress = 0;
        try
        {
            await using (var source = await response.Content.ReadAsStreamAsync(cancellationToken))
            await using (var file = File.Create(partial))
            {
                var buffer = new byte[1 << 20];
                long received = 0;
                int read;
                while ((read = await source.ReadAsync(buffer, cancellationToken)) > 0)
                {
                    await file.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                    received += read;
                    if (total > 0) DownloadProgress = (double)received / total.Value;
                }
                if (total is { } expected && received != expected)
                    throw new IOException($"Download incompleto do modelo de voz ({received} de {expected} bytes)");
            }
            File.Move(partial, path, overwrite: true);
        }
        finally
        {
            DownloadProgress = null;
            if (File.Exists(partial)) File.Delete(partial);
        }
    }
}
