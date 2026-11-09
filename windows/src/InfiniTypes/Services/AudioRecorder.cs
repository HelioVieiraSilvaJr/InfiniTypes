using System.Runtime.InteropServices;
using InfiniTypes.Core.Transcription;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace InfiniTypes.App.Services;

/// <summary>Grava o microfone padrão pelo WASAPI e entrega 16 kHz mono, o formato do Whisper.</summary>
internal sealed class AudioRecorder
{
    private readonly Lock _gate = new();
    private WasapiRecorder? _recorder;
    private WaveFormat _format = WaveFormat.CreateIeeeFloatWaveFormat(ITranscriber.SampleRate, 1);
    private List<float> _samples = [];
    private float _level;

    /// <summary>Nível de 0 a 1 do último trecho gravado, para o medidor do HUD.</summary>
    public float Level
    {
        get { lock (_gate) return _level; }
    }

    public void Start()
    {
        Stop();
        try
        {
            var recorder = new WasapiRecorderBuilder()
                // Segue o microfone padrão se ele mudar no meio da gravação (fone conectado, por exemplo).
                .WithDefaultDeviceStreamRouting()
                // No modo compartilhado o próprio Windows converte para o formato pedido.
                .WithFormat(WaveFormat.CreateIeeeFloatWaveFormat(ITranscriber.SampleRate, 1))
                .Build();
            _format = recorder.WaveFormat;
            lock (_gate) _samples = new List<float>(_format.SampleRate * 30);
            recorder.DataAvailable += OnData;
            recorder.StartRecording();
            _recorder = recorder;
        }
        catch (Exception error) when (error is COMException or InvalidOperationException or NotSupportedException)
        {
            Log.Error($"Microfone indisponível: {error.Message}");
            throw new InvalidOperationException(
                "Não consegui abrir o microfone. Confira em Configurações → Privacidade e segurança → Microfone " +
                "se o acesso de apps da área de trabalho está ligado.", error);
        }
    }

    /// <summary>Para a gravação e devolve as amostras já convertidas.</summary>
    public float[] Stop()
    {
        var recorder = _recorder;
        if (recorder is null) return [];
        _recorder = null;
        recorder.DataAvailable -= OnData;
        recorder.StopRecording();
        recorder.Dispose();
        float[] recorded;
        lock (_gate)
        {
            recorded = [.. _samples];
            _samples = [];
            _level = 0;
        }
        return AudioConverter.Resample(recorded, _format.SampleRate, ITranscriber.SampleRate);
    }

    private void OnData(ReadOnlySpan<byte> buffer, AudioClientBufferFlags flags, long devicePosition, long qpcPosition)
    {
        if (buffer.IsEmpty) return;
        var decoded = (flags & AudioClientBufferFlags.Silent) != 0
            ? new float[buffer.Length / Math.Max(_format.BlockAlign / Math.Max(_format.Channels, 1), 1)]
            : Decode(buffer, _format);
        var mono = AudioConverter.Mono(decoded, _format.Channels);
        lock (_gate)
        {
            _samples.AddRange(mono);
            _level = AudioConverter.Level(mono);
        }
    }

    private static float[] Decode(ReadOnlySpan<byte> buffer, WaveFormat format)
    {
        var isFloat = format.Encoding == WaveFormatEncoding.IeeeFloat
            || (format is WaveFormatExtensible extensible && extensible.SubFormat == AudioMediaSubtypes.MEDIASUBTYPE_IEEE_FLOAT);
        switch (format.BitsPerSample)
        {
            case 32 when isFloat:
                return MemoryMarshal.Cast<byte, float>(buffer).ToArray();
            case 16:
            {
                var shorts = MemoryMarshal.Cast<byte, short>(buffer);
                var samples = new float[shorts.Length];
                for (var i = 0; i < shorts.Length; i++) samples[i] = shorts[i] / 32768f;
                return samples;
            }
            case 24:
            {
                var samples = new float[buffer.Length / 3];
                for (var i = 0; i < samples.Length; i++)
                    samples[i] = ((buffer[i * 3] << 8 | buffer[i * 3 + 1] << 16 | buffer[i * 3 + 2] << 24) >> 8) / 8388608f;
                return samples;
            }
            case 32:
            {
                var ints = MemoryMarshal.Cast<byte, int>(buffer);
                var samples = new float[ints.Length];
                for (var i = 0; i < ints.Length; i++) samples[i] = ints[i] / 2147483648f;
                return samples;
            }
            default:
                throw new NotSupportedException($"Formato de áudio sem suporte: {format}");
        }
    }
}
