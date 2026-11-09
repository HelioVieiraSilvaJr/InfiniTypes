namespace InfiniTypes.Core.Transcription;

/// <summary>Converte o áudio do microfone para o formato do Whisper: 16 kHz, mono, float.</summary>
public static class AudioConverter
{
    /// <summary>Média dos canais intercalados.</summary>
    public static float[] Mono(ReadOnlySpan<float> interleaved, int channels)
    {
        if (channels <= 1) return interleaved.ToArray();
        var frames = interleaved.Length / channels;
        var mono = new float[frames];
        for (var frame = 0; frame < frames; frame++)
        {
            var sum = 0f;
            for (var channel = 0; channel < channels; channel++) sum += interleaved[frame * channels + channel];
            mono[frame] = sum / channels;
        }
        return mono;
    }

    /// <summary>
    /// Reamostra com um filtro passa-baixa simples (média móvel do tamanho da razão) e interpolação linear.
    /// Para a fala, que fica abaixo de 8 kHz, isso basta e evita depender do resampler da biblioteca de áudio.
    /// </summary>
    public static float[] Resample(float[] samples, int fromRate, int toRate)
    {
        if (fromRate == toRate || samples.Length == 0) return samples;
        var ratio = (double)fromRate / toRate;
        var source = ratio > 1 ? MovingAverage(samples, (int)Math.Ceiling(ratio)) : samples;
        var length = (int)(samples.Length / ratio);
        var output = new float[length];
        for (var i = 0; i < length; i++)
        {
            var position = i * ratio;
            var index = (int)position;
            var fraction = (float)(position - index);
            var next = Math.Min(index + 1, source.Length - 1);
            output[i] = source[index] + (source[next] - source[index]) * fraction;
        }
        return output;
    }

    /// <summary>Nível de 0 a 1 para o medidor do HUD.</summary>
    public static float Level(ReadOnlySpan<float> samples)
    {
        if (samples.IsEmpty) return 0;
        double sum = 0;
        foreach (var sample in samples) sum += sample * sample;
        var rms = Math.Sqrt(sum / samples.Length);
        // Fala normal fica em torno de -30 dB; o medidor vai de -50 dB a 0.
        var decibels = 20 * Math.Log10(Math.Max(rms, 1e-6));
        return (float)Math.Clamp((decibels + 50) / 50, 0, 1);
    }

    private static float[] MovingAverage(float[] samples, int width)
    {
        if (width <= 1) return samples;
        var output = new float[samples.Length];
        double sum = 0;
        for (var i = 0; i < samples.Length; i++)
        {
            sum += samples[i];
            if (i >= width) sum -= samples[i - width];
            output[i] = (float)(sum / Math.Min(i + 1, width));
        }
        return output;
    }
}
