namespace InfiniTypes.Core.Transcription;

/// <summary>Fala em texto, no próprio computador.</summary>
public interface ITranscriber
{
    /// <summary>Taxa das amostras recebidas: 16 kHz mono, como o Whisper espera.</summary>
    public const int SampleRate = 16_000;

    bool IsReady { get; }

    /// <param name="vocabulary">Termos do glossário, que orientam o reconhecimento.</param>
    Task<string> TranscribeAsync(float[] samples, IReadOnlyList<string> vocabulary, CancellationToken cancellationToken = default);
}
