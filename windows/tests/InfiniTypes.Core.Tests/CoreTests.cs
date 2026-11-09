using InfiniTypes.Core.Input;
using InfiniTypes.Core.Refinement;
using InfiniTypes.Core.Storage;

namespace InfiniTypes.Core.Tests;

public sealed class HotkeyLogicTests
{
    private const int RightControl = HotkeyLogic.RightControl;
    private const int RightShift = HotkeyLogic.RightShift;
    private const int LeftControl = 0xA2;
    private const int KeyC = 0x43;

    [Fact]
    public void HoldingRightControlDictatesAPrompt()
    {
        var logic = new HotkeyLogic();
        Assert.Equal(HotkeyEvent.Press(DictationMode.Prompt), logic.KeyDown(RightControl, false, 0));
        Assert.Null(logic.KeyDown(RightControl, false, 0.5));
        Assert.Equal(HotkeyEvent.Release, logic.KeyUp(RightControl, 3));
    }

    [Fact]
    public void HoldingRightShiftDictatesLiterally()
    {
        var logic = new HotkeyLogic();
        Assert.Equal(HotkeyEvent.Press(DictationMode.Literal), logic.KeyDown(RightShift, false, 0));
    }

    [Fact]
    public void AnotherKeyCancels()
    {
        var logic = new HotkeyLogic();
        logic.KeyDown(RightControl, false, 0);
        Assert.Equal(HotkeyEvent.Cancel, logic.KeyDown(KeyC, true, 0.1));
        Assert.Null(logic.KeyDown(KeyC, true, 0.2));
        Assert.Null(logic.KeyUp(RightControl, 0.3));
    }

    [Fact]
    public void LeftControlAndCombinationsAreIgnored()
    {
        var logic = new HotkeyLogic();
        Assert.Null(logic.KeyDown(LeftControl, false, 0));
        Assert.Null(logic.KeyDown(RightControl, true, 0.1));
    }

    [Fact]
    public void TapThenHoldRevisesTheSelection()
    {
        var logic = new HotkeyLogic();
        logic.KeyDown(RightControl, false, 0);
        logic.KeyUp(RightControl, 0.15);
        Assert.Equal(HotkeyEvent.Press(DictationMode.Revision), logic.KeyDown(RightControl, false, 0.35));
    }

    [Fact]
    public void SlowSecondPressIsAPrompt()
    {
        var logic = new HotkeyLogic();
        logic.KeyDown(RightControl, false, 0);
        logic.KeyUp(RightControl, 0.15);
        Assert.Equal(HotkeyEvent.Press(DictationMode.Prompt), logic.KeyDown(RightControl, false, 1.0));
    }

    [Fact]
    public void LongFirstHoldIsNotATap()
    {
        var logic = new HotkeyLogic();
        logic.KeyDown(RightControl, false, 0);
        logic.KeyUp(RightControl, 2);
        Assert.Equal(HotkeyEvent.Press(DictationMode.Prompt), logic.KeyDown(RightControl, false, 2.2));
    }

    [Fact]
    public void DoubleTapOnRightShiftStartsHandsFreeUntilTheNextTap()
    {
        var logic = new HotkeyLogic();
        logic.KeyDown(RightShift, false, 0);
        logic.KeyUp(RightShift, 0.1);
        Assert.Equal(HotkeyEvent.HandsFree, logic.KeyDown(RightShift, false, 0.3));
        // Soltar a tecla não termina, e digitar no meio da fala também não.
        Assert.Null(logic.KeyUp(RightShift, 0.4));
        Assert.Null(logic.KeyDown(KeyC, false, 1));
        // Uma maiúscula com o Shift direito também não.
        Assert.Null(logic.KeyDown(RightShift, false, 2));
        Assert.Null(logic.KeyDown(KeyC, true, 2.1));
        Assert.Null(logic.KeyUp(RightShift, 2.2));
        Assert.True(logic.IsHandsFree);
        // Um toque isolado termina.
        Assert.Null(logic.KeyDown(RightShift, false, 5));
        Assert.Equal(HotkeyEvent.Release, logic.KeyUp(RightShift, 5.1));
        Assert.False(logic.IsHandsFree);
    }

    [Fact]
    public void EscapeCancelsHandsFree()
    {
        var logic = new HotkeyLogic();
        logic.KeyDown(RightShift, false, 0);
        logic.KeyUp(RightShift, 0.1);
        logic.KeyDown(RightShift, false, 0.3);
        logic.KeyUp(RightShift, 0.4);
        Assert.Equal(HotkeyEvent.Cancel, logic.KeyDown(HotkeyLogic.Escape, false, 1));
        Assert.Equal(HotkeyEvent.Press(DictationMode.Prompt), logic.KeyDown(RightControl, false, 2));
    }

    [Fact]
    public void TypingBetweenTapsResetsTheDoubleTap()
    {
        var logic = new HotkeyLogic();
        logic.KeyDown(RightControl, false, 0);
        logic.KeyUp(RightControl, 0.1);
        logic.KeyDown(KeyC, false, 0.2);
        Assert.Equal(HotkeyEvent.Press(DictationMode.Prompt), logic.KeyDown(RightControl, false, 0.3));
    }
}

public sealed class ModelCatalogTests
{
    [Fact]
    public void MergeKeepsKnownModelsFirstWithoutDuplicates()
    {
        var merged = ModelCatalog.Merge([new("claude-sonnet-5-5", "Claude Sonnet 5.5"), new("claude-haiku-4-5", "Claude Haiku 4.5")]);
        Assert.Equal(ModelCatalog.Known.Select(m => m.Id), merged.Take(ModelCatalog.Known.Count).Select(m => m.Id));
        Assert.Equal(ModelCatalog.Known.Count + 1, merged.Count);
        Assert.Equal("claude-haiku-4-5", merged[^1].Id);
        Assert.False(merged[^1].SupportsEffort);
    }

    [Fact]
    public void PriceLabelUsesBrazilianFormat()
    {
        Assert.Equal("US$ 4 / 20 por milhão de tokens", ModelCatalog.Model("claude-opus-5-5").PriceLabel);
        Assert.Equal("US$ 0,10 / 0,50 por milhão de tokens", ModelCatalog.Model("claude-haiku-5-5").PriceLabel);
        Assert.Null(ModelCatalog.Model("claude-desconhecido").PriceLabel);
    }

    [Fact]
    public void RetriesOnlyTransientErrors()
    {
        Assert.True(new AnthropicException(AnthropicErrorKind.Http, 429).IsRetryable);
        Assert.True(new AnthropicException(AnthropicErrorKind.Http, 529).IsRetryable);
        Assert.False(new AnthropicException(AnthropicErrorKind.Http, 401).IsRetryable);
        Assert.False(new AnthropicException(AnthropicErrorKind.Refusal).IsRetryable);
    }
}

public sealed class PromptTests
{
    [Theory]
    [InlineData("SystemPrompt", "<transcricao>")]
    [InlineData("LiteralPrompt", "<transcricao>")]
    [InlineData("RevisionPrompt", "{{formato}}")]
    [InlineData("RevisionFormatEdits", "`original`")]
    [InlineData("RevisionFormatFullText", "texto completo")]
    public void PromptsAreEmbedded(string resource, string marker) =>
        Assert.Contains(marker, Prompts.Load(resource));

    [Fact]
    public void RevisionPromptTakesTheFormatInstructions() =>
        Assert.Equal("Regras.\n\nResponda em JSON.\n", ClaudeRefiner.RevisionPrompt("Regras.\n\n{{formato}}\n", "\nResponda em JSON.\n"));

    [Fact]
    public void RefinerLoadsEveryPrompt()
    {
        var refiner = new ClaudeRefiner(() => null, () => (ModelCatalog.DefaultModelId, Effort.Low));
        Assert.NotNull(refiner);
    }
}

public sealed class HistoryStoreTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), $"InfiniTypesTests-{Guid.NewGuid():N}");

    [Fact]
    public void SavesSearchesAndUpdatesRecords()
    {
        using var store = new HistoryStore(Path.Combine(_folder, "History.db"));
        var older = new DictationRecord
        {
            CreatedAt = new DateTimeOffset(2026, 11, 6, 13, 2, 57, TimeSpan.Zero), Text = "Crie um teste", RawTranscript = "crie um teste",
            AppName = "Code", Mode = DictationMode.Prompt, ModelId = "claude-sonnet-5-5", Refined = true, AudioSeconds = 3,
            TranscriptionSeconds = 1.2,
        };
        var newer = new DictationRecord
        {
            CreatedAt = new DateTimeOffset(2026, 11, 6, 14, 25, 16, TimeSpan.Zero), Text = "- Darth Vader (1)",
            RawTranscript = "adicione a ordem", OriginalText = "- Darth Vader", AppName = "Notepad", Mode = DictationMode.Revision,
            Refined = true, AudioSeconds = 2, TranscriptionSeconds = 0.8, RefinementSeconds = 1.5, InputTokens = 900,
            OutputTokens = 40,
        };
        store.Insert(older);
        store.Insert(newer);

        var all = store.Records();
        Assert.Equal([newer.Id, older.Id], all.Select(r => r.Id));
        Assert.Equal(DictationMode.Revision, all[0].Mode);
        Assert.Equal("- Darth Vader", all[0].OriginalText);
        Assert.Equal(900, all[0].InputTokens);
        Assert.Null(all[1].RefinementSeconds);
        Assert.Single(store.Records("vader"));

        older.InEvalSet = true;
        older.Pasted = true;
        store.Update(older);
        var marked = Assert.Single(store.EvalSet());
        Assert.True(marked.Pasted);

        store.Delete(newer.Id);
        Assert.Single(store.Records());
    }

    [Fact]
    public void ExportsOneSortedLinePerCaseWithSnakeCaseKeys()
    {
        var newer = new EvalCase("2026-11-06T14:25:16Z", "revision", "Notepad", null, null, "adicione a ordem", "- Darth Vader",
            "- Darth Vader (1)", "claude-sonnet-5-5", true);
        var older = newer with { Id = "2026-11-06T13:02:57Z", Mode = "prompt", OriginalText = null };

        var lines = EvalExporter.Jsonl([newer, older]).Split('\n', StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal(2, lines.Length);
        Assert.Contains("\"id\":\"2026-11-06T13:02:57Z\"", lines[0]);
        Assert.Contains("\"original_text\":\"- Darth Vader\"", lines[1]);
        Assert.Contains("\"raw_transcript\":\"adicione a ordem\"", lines[1]);
    }

    [Fact]
    public void SettingsSurviveARoundTripAndBadFilesFallBack()
    {
        var store = new JsonFileStore<AppSettings>(Path.Combine(_folder, "Settings.json"));
        Assert.Equal(ModelCatalog.DefaultModelId, store.Load().ModelId);
        store.Save(new AppSettings { ModelId = "claude-haiku-5-5", Effort = "high" });
        Assert.Equal("claude-haiku-5-5", store.Load().ModelId);

        File.WriteAllText(store.Path, "{ quebrado");
        Assert.Equal(ModelCatalog.DefaultModelId, store.Load().ModelId);
    }

    public void Dispose()
    {
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
        if (Directory.Exists(_folder)) Directory.Delete(_folder, recursive: true);
    }
}

public sealed class AudioConverterTests
{
    [Fact]
    public void MixesChannelsAndResamplesTo16Kilohertz()
    {
        // 1 s de um tom de 440 Hz em estéreo a 48 kHz.
        var stereo = new float[48_000 * 2];
        for (var i = 0; i < 48_000; i++)
        {
            var value = (float)Math.Sin(2 * Math.PI * 440 * i / 48_000);
            stereo[i * 2] = value;
            stereo[i * 2 + 1] = value;
        }
        var mono = Transcription.AudioConverter.Mono(stereo, 2);
        Assert.Equal(48_000, mono.Length);

        var resampled = Transcription.AudioConverter.Resample(mono, 48_000, 16_000);
        Assert.Equal(16_000, resampled.Length);
        // O tom continua com amplitude próxima de 1 depois do filtro.
        Assert.InRange(resampled.Skip(100).Max(), 0.9f, 1.0f);
    }

    [Fact]
    public void SilenceHasNoLevel()
    {
        Assert.Equal(0, Transcription.AudioConverter.Level(new float[1600]));
        Assert.InRange(Transcription.AudioConverter.Level(Enumerable.Repeat(0.5f, 1600).ToArray()), 0.8f, 1f);
    }
}

public sealed class DayGroupingTests
{
    [Fact]
    public void TitlesTodayYesterdayAndOlderDays()
    {
        var now = new DateTime(2026, 11, 6, 15, 0, 0);
        Assert.Equal("Hoje", DayGrouping.Title(new DateTime(2026, 11, 6, 9, 0, 0), now));
        Assert.Equal("Ontem", DayGrouping.Title(new DateTime(2026, 11, 5, 22, 0, 0), now));
        Assert.Equal("31 de outubro de 2026", DayGrouping.Title(new DateTime(2026, 10, 31, 8, 0, 0), now));
    }
}
