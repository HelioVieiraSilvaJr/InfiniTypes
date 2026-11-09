using System.Diagnostics;
using InfiniTypes.App.Services;
using InfiniTypes.App.UI;
using InfiniTypes.Core;
using InfiniTypes.Core.Refinement;
using InfiniTypes.Core.Storage;
using InfiniTypes.Core.Transcription;

namespace InfiniTypes.App;

/// <summary>Orquestra o ditado: grava → transcreve → refina (ou revisa a seleção) → salva no histórico → cola.</summary>
internal sealed class DictationCoordinator(
    AppState state,
    WhisperTranscriber transcriber,
    ClaudeRefiner refiner,
    HistoryStore history,
    HudWindow hud)
{
    private enum Phase
    {
        /// <summary>Atalho pressionado, esperando um instante antes de abrir o microfone.</summary>
        Arming,
        Recording,
        Processing,
        Idle,
    }

    private const double MinimumAudioSeconds = 0.5;
    private static readonly TimeSpan MaximumAudio = TimeSpan.FromMinutes(5);
    /// <summary>Toques rápidos (ex.: Shift direito + letra) terminam antes disso e não abrem o microfone.</summary>
    private static readonly TimeSpan LiteralArmingDelay = TimeSpan.FromMilliseconds(150);
    /// <summary>O HUD só aparece depois disso, para atalhos cancelados não piscarem na tela.</summary>
    private static readonly TimeSpan HudDelay = TimeSpan.FromMilliseconds(300);
    /// <summary>Limite do texto selecionado enviado à API na revisão.</summary>
    public const int MaxSelectionCharacters = 15_000;

    private readonly AudioRecorder _recorder = new();
    private Phase _phase = Phase.Idle;
    private DictationMode _mode;
    private DictationContext _context = DictationContext.Empty;
    private Task<Selection> _selection = Task.FromResult(Selection.Nothing);
    private Stopwatch? _recordingClock;
    private CancellationTokenSource? _pending;

    public async void StartRecording(DictationMode mode)
    {
        if (_phase != Phase.Idle) return;
        _mode = mode;
        _context = ContextCollector.Capture();
        // A seleção é lida enquanto a tecla está segurada: na revisão é o texto a revisar; nos outros modos
        // serve para avisar que o texto colado vai substituí-la.
        _selection = SelectionReader.AutomationSelectionAsync();
        _phase = Phase.Arming;
        var pending = NewPending();
        if (mode == DictationMode.Literal)
        {
            try
            {
                await Task.Delay(LiteralArmingDelay, pending.Token);
            }
            catch (TaskCanceledException)
            {
                return;
            }
            if (_phase != Phase.Arming) return;
        }
        BeginCapture();

        // O microfone abre na hora; se a seleção estiver num campo de senha, a revisão é desfeita.
        if (mode == DictationMode.Revision && await _selection is Selection.SecureField && _phase == Phase.Recording)
        {
            _pending?.Cancel();
            _recorder.Stop();
            _phase = Phase.Idle;
            hud.ShowFailure("Campo de senha: a revisão por voz não lê esse conteúdo");
        }
    }

    public void CancelRecording()
    {
        switch (_phase)
        {
            case Phase.Arming:
                _pending?.Cancel();
                _phase = Phase.Idle;
                break;
            case Phase.Recording:
                var wasVisible = HudIsVisible;
                _pending?.Cancel();
                _recorder.Stop();
                _phase = Phase.Idle;
                if (wasVisible) hud.ShowNotice("Ditado cancelado");
                else hud.HideNow();
                break;
        }
    }

    public async void FinishRecording()
    {
        switch (_phase)
        {
            case Phase.Arming:
                // Foi só um toque na tecla.
                _pending?.Cancel();
                _phase = Phase.Idle;
                return;
            case Phase.Recording:
                _pending?.Cancel();
                var samples = _recorder.Stop();
                var audioSeconds = (double)samples.Length / ITranscriber.SampleRate;
                if (audioSeconds < MinimumAudioSeconds)
                {
                    _phase = Phase.Idle;
                    hud.HideNow();
                    return;
                }
                _phase = Phase.Processing;
                try
                {
                    await ProcessAsync(samples, audioSeconds, _mode, _context, _selection);
                }
                catch (Exception error)
                {
                    Log.Error($"Falha inesperada no ditado: {error}");
                    hud.ShowFailure($"Algo deu errado: {error.Message}");
                }
                finally
                {
                    _phase = Phase.Idle;
                }
                return;
        }
    }

    private async void BeginCapture()
    {
        try
        {
            _recorder.Start();
        }
        catch (InvalidOperationException error)
        {
            _phase = Phase.Idle;
            hud.ShowFailure(error.Message);
            return;
        }
        _phase = Phase.Recording;
        _recordingClock = Stopwatch.StartNew();
        var pending = NewPending();
        try
        {
            // Na revisão o gesto é intencional: o aviso aparece na hora, confirmando o modo.
            if (_mode != DictationMode.Revision) await Task.Delay(HudDelay, pending.Token);
            if (_phase == Phase.Recording) hud.ShowRecording(RecordingLabel(), () => _recorder.Level);
            await Task.Delay(MaximumAudio - HudDelay, pending.Token);
            if (_phase == Phase.Recording) FinishRecording();
        }
        catch (TaskCanceledException)
        {
            // Soltou a tecla ou cancelou.
        }
    }

    private string RecordingLabel()
    {
        var selection = _selection.IsCompletedSuccessfully ? _selection.Result : Selection.Nothing;
        return (_mode, selection) switch
        {
            (DictationMode.Revision, Selection.Text text) => $"Ouvindo (revisão de {WordCount(text.Value)} palavras)…",
            (DictationMode.Revision, _) => "Ouvindo (revisão da seleção)…",
            (DictationMode.Literal, Selection.Text) => "Ouvindo (literal; vai substituir a seleção)…",
            (DictationMode.Literal, _) => "Ouvindo (literal)…",
            (_, Selection.Text) => "Ouvindo (prompt novo; vai substituir a seleção)…",
            _ => "Ouvindo…",
        };
    }

    private bool HudIsVisible =>
        _recordingClock is { } clock && (_mode == DictationMode.Revision || clock.Elapsed >= HudDelay);

    private CancellationTokenSource NewPending()
    {
        _pending?.Cancel();
        _pending = new CancellationTokenSource();
        return _pending;
    }

    // Processamento

    private sealed record Transcription(string Text, double Seconds, double AudioSeconds, IReadOnlyList<string> Vocabulary,
        DictationContext Context);

    private async Task ProcessAsync(float[] samples, double audioSeconds, DictationMode mode, DictationContext context,
        Task<Selection> selectionTask)
    {
        var match = state.Glossary.Match(context.WindowTitle);
        context = context with { ProjectName = match.ProjectName };

        hud.ShowWorking(transcriber.IsReady ? "Transcrevendo…" : "Carregando o modelo de voz…",
            () => transcriber.DownloadProgress is { } progress ? $"Baixando o modelo de voz ({progress:P0})…" : null);
        var clock = Stopwatch.StartNew();
        string text;
        try
        {
            text = HallucinationFilter.Clean(await transcriber.TranscribeAsync(samples, match.Terms));
        }
        catch (Exception error)
        {
            Log.Error($"Falha na transcrição: {error.Message}");
            hud.ShowFailure($"Falha na transcrição: {error.Message}");
            return;
        }
        if (text.Length == 0)
        {
            hud.ShowNotice("Nada foi reconhecido");
            return;
        }
        var transcription = new Transcription(text, clock.Elapsed.TotalSeconds, audioSeconds, match.Terms, context);

        var selection = await selectionTask;
        if (mode != DictationMode.Revision)
        {
            await RefineAndPasteAsync(transcription, mode, replacesSelection: selection is Selection.Text);
            return;
        }
        // Se a Automação da Interface não mostrou a seleção, um Ctrl+C a revela, agora que o atalho já foi solto.
        if (selection is Selection.None) selection = await SelectionReader.CopySelectionAsync(TimeSpan.FromMilliseconds(1500));
        if (selection is not Selection.Text { Value: var original })
        {
            // Você pediu revisão: colar um prompt novo poderia apagar uma seleção que o app só não
            // conseguiu ler. Nada é colado, e a fala fica no histórico.
            Save(transcription, DictationMode.Revision, transcription.Text, refined: false,
                error: "Não foi possível ler o texto selecionado");
            hud.ShowFailure("Não consegui ler o texto selecionado, então não alterei nada. A fala ficou no histórico.");
            return;
        }
        await ReviseAsync(original, transcription);
    }

    private async Task RefineAndPasteAsync(Transcription transcription, DictationMode mode, bool replacesSelection)
    {
        // Se o refinamento falhar, o ditado segue com a transcrição bruta: nada se perde.
        var model = ModelCatalog.Model(state.Settings.ModelId);
        var action = mode == DictationMode.Literal ? "Limpando" : "Refinando";
        var warning = replacesSelection ? " (o resultado vai substituir o texto selecionado)" : "";
        hud.ShowWorking($"{action} com {model.DisplayName}…{warning}");
        var clock = Stopwatch.StartNew();
        RefinementResult? result = null;
        string? refinementError = null;
        try
        {
            result = await refiner.RefineAsync(transcription.Text, transcription.Context, mode, transcription.Vocabulary);
        }
        catch (Exception error) when (error is AnthropicException or HttpRequestException)
        {
            refinementError = error.Message;
            Log.Error($"Falha no refinamento: {error.Message}");
        }

        // Salva antes de tentar colar.
        var record = Save(transcription, mode, result?.Text ?? transcription.Text, refined: result is not null,
            error: refinementError, refinementSeconds: clock.Elapsed.TotalSeconds,
            tokens: (result?.InputTokens, result?.OutputTokens));

        if (await FocusDetector.CheckAsync(transcription.Context.AppId) == FocusKind.NotEditable)
        {
            hud.ShowNotice("Salvo no histórico: nenhum campo de texto em foco");
            return;
        }
        await TextInserter.PasteAsync(record.Text, transcription.Context.AppId);
        record.Pasted = true;
        history.Update(record);

        if (refinementError is not null)
            hud.ShowFailure($"Não entre em pânico: colei o texto sem refinar. {refinementError}");
        else if (replacesSelection)
            hud.ShowNotice("Colado no lugar do texto selecionado: Ctrl+Z desfaz. Para revisar uma seleção, toque e segure o Ctrl direito.");
        else
            hud.ShowSuccess(mode == DictationMode.Literal ? "Texto colado" : "Prompt colado");
    }

    private async Task ReviseAsync(string original, Transcription transcription)
    {
        // Salvaguardas antes de mandar o texto selecionado para a API.
        var secrets = SecretScanner.Findings(original);
        if (secrets.Count > 0)
        {
            // O texto com o segredo não vai para o histórico; só a fala.
            var found = string.Join(", ", secrets);
            Save(transcription, DictationMode.Revision, transcription.Text, refined: false,
                error: $"Seleção não enviada: parece conter {found}");
            hud.ShowFailure($"Nada foi enviado: a seleção parece conter {found}. A fala ficou no histórico.");
            return;
        }
        if (original.Length > MaxSelectionCharacters)
        {
            Save(transcription, DictationMode.Revision, transcription.Text, original: original, refined: false,
                error: $"Seleção grande demais ({original.Length} caracteres)");
            hud.ShowFailure($"Seleção grande demais para revisar ({original.Length} caracteres; o limite é {MaxSelectionCharacters}). A fala ficou no histórico.");
            return;
        }

        var model = ModelCatalog.Model(state.Settings.ModelId);
        hud.ShowWorking($"Revisando “{Preview(original)}” com {model.DisplayName}…");
        var clock = Stopwatch.StartNew();
        RevisionResult result;
        try
        {
            result = await refiner.ReviseAsync(original, transcription.Text, transcription.Context, transcription.Vocabulary);
        }
        catch (Exception error) when (error is AnthropicException or HttpRequestException)
        {
            Log.Error($"Falha na revisão: {error.Message}");
            Save(transcription, DictationMode.Revision, transcription.Text, original: original, refined: false,
                error: error.Message, refinementSeconds: clock.Elapsed.TotalSeconds);
            hud.ShowFailure($"Não entre em pânico: a revisão falhou e seu texto continua intacto. {error.Message}");
            return;
        }

        var record = Save(transcription, DictationMode.Revision, result.Text, original: original, refined: true, error: null,
            refinementSeconds: clock.Elapsed.TotalSeconds, tokens: (result.InputTokens, result.OutputTokens));
        Log.Info($"Revisão: {(result.EditCount is { } count ? $"{count} alterações" : "texto reescrito")}, {original.Length} → {result.Text.Length} caracteres");

        if (result.EditCount == 0)
        {
            hud.ShowNotice("A fala não pediu alterações: o texto foi mantido");
            return;
        }
        if (FocusDetector.IsTerminal(transcription.Context.AppId))
        {
            // No terminal, colar não substitui a seleção: acrescentaria o texto no cursor.
            await TextInserter.CopyAsync(result.Text);
            hud.ShowNotice("Revisão copiada: apague o texto antigo no terminal e cole com Ctrl+V");
            return;
        }
        if (await FocusDetector.CheckAsync(transcription.Context.AppId) == FocusKind.NotEditable)
        {
            hud.ShowNotice("Revisão salva no histórico: nenhum campo de texto em foco");
            return;
        }
        await TextInserter.PasteAsync(result.Text, transcription.Context.AppId);
        record.Pasted = true;
        history.Update(record);

        // Na reescrita completa, um texto bem mais curto sugere que algo se perdeu.
        if (result.EditCount is null && result.Text.Length < original.Length * 0.7)
            hud.ShowFailure("Revisão colada, mas ficou bem mais curta que o original. Confira: Ctrl+Z desfaz, e o original está no histórico.");
        else
            hud.ShowSuccess(result.EditCount switch
            {
                1 => "Revisão colada (1 alteração)",
                { } edits => $"Revisão colada ({edits} alterações)",
                null => "Revisão colada",
            });
    }

    private DictationRecord Save(Transcription transcription, DictationMode mode, string text, bool refined, string? error,
        string? original = null, double? refinementSeconds = null, (int? Input, int? Output) tokens = default)
    {
        var record = new DictationRecord
        {
            Text = text,
            RawTranscript = transcription.Text,
            AppName = transcription.Context.AppName,
            AppId = transcription.Context.AppId,
            WindowTitle = transcription.Context.WindowTitle,
            ProjectName = transcription.Context.ProjectName,
            Mode = mode,
            OriginalText = original,
            ModelId = state.Settings.ModelId,
            Refined = refined,
            ErrorMessage = error,
            AudioSeconds = transcription.AudioSeconds,
            TranscriptionSeconds = transcription.Seconds,
            RefinementSeconds = refinementSeconds,
            InputTokens = tokens.Input,
            OutputTokens = tokens.Output,
        };
        history.Insert(record);
        Log.Info($"Ditado {mode.RawValue()}: áudio {transcription.AudioSeconds:F1} s, transcrição {transcription.Seconds:F2} s, " +
                 $"refinamento {refinementSeconds ?? 0:F2} s ({state.Settings.ModelId}, tokens {tokens.Input ?? 0}/{tokens.Output ?? 0}, " +
                 $"glossário {transcription.Vocabulary.Count} termos, projeto {transcription.Context.ProjectName ?? "-"})");
        return record;
    }

    private static int WordCount(string text) =>
        text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;

    /// <summary>Começo do texto, para o HUD mostrar o que foi capturado.</summary>
    private static string Preview(string text)
    {
        var flat = string.Join(' ', text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return flat.Length > 40 ? flat[..40] + "…" : flat;
    }
}
