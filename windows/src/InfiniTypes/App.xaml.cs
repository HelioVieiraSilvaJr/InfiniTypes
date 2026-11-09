using System.Windows;
using System.Windows.Threading;
using InfiniTypes.App.Services;
using InfiniTypes.App.UI;
using InfiniTypes.Core.Refinement;
using InfiniTypes.Core.Storage;
using InfiniTypes.Core.Transcription;

namespace InfiniTypes.App;

public partial class App : Application
{
    private Mutex? _singleInstance;
    private TrayIcon? _tray;
    private KeyboardHook? _hook;
    private WhisperTranscriber? _transcriber;
    private HistoryStore? _history;
    private HistoryWindow? _historyWindow;
    private SettingsWindow? _settingsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _singleInstance = new Mutex(initiallyOwned: true, @"Local\InfiniTypes", out var isFirst);
        if (!isFirst)
        {
            MessageBox.Show("O InfiniTypes já está aberto: procure o ícone na área de notificação.", "InfiniTypes");
            Shutdown();
            return;
        }

        DispatcherUnhandledException += (_, args) =>
        {
            Log.Error($"Erro não tratado: {args.Exception}");
            args.Handled = true;
        };
        HallucinationFilter.Log = Log.Info;
        Log.Info($"InfiniTypes {typeof(App).Assembly.GetName().Version} iniciado");

        var state = new AppState();
        _history = new HistoryStore(AppPaths.History);
        _transcriber = new WhisperTranscriber();
        var refiner = new ClaudeRefiner(CredentialStore.ApiKey, () => (state.Settings.ModelId, state.Effort)) { Log = Log.Info };
        var hud = new HudWindow();
        var coordinator = new DictationCoordinator(state, _transcriber, refiner, _history, hud);

        _tray = new TrayIcon(OpenHistory, () => OpenSettings(state), Quit);
        _hook = new KeyboardHook(Dispatcher);
        _hook.Pressed += coordinator.StartRecording;
        _hook.HandsFreeStarted += coordinator.StartHandsFree;
        coordinator.RecordingEnded += _hook.EndHandsFree;
        _hook.Released += coordinator.FinishRecording;
        _hook.Cancelled += coordinator.CancelRecording;
        _hook.Start();

        // O modelo de voz é baixado e carregado em segundo plano, para o primeiro ditado não esperar.
        _ = PrepareTranscriberAsync(_transcriber);

        if (CredentialStore.ApiKey() is null)
        {
            OpenSettings(state);
            _tray.ShowTip("InfiniTypes", "Cole a sua chave da API da Anthropic para os prompts saírem refinados.");
        }
        else
        {
            _tray.ShowTip("InfiniTypes está ativo", "Segure o Ctrl direito, fale e solte: o prompt é colado no cursor.");
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hook?.Dispose();
        _tray?.Dispose();
        _transcriber?.Dispose();
        _history?.Dispose();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }

    private static async Task PrepareTranscriberAsync(WhisperTranscriber transcriber)
    {
        try
        {
            await transcriber.PrepareAsync();
        }
        catch (Exception error)
        {
            // O primeiro ditado tenta de novo e mostra o erro no HUD.
            Log.Error($"Modelo de voz indisponível: {error.Message}");
        }
    }

    private void OpenHistory()
    {
        if (_historyWindow is null)
        {
            _historyWindow = new HistoryWindow(_history!);
            _historyWindow.Closed += (_, _) => _historyWindow = null;
            _historyWindow.Show();
        }
        Bring(_historyWindow);
    }

    private void OpenSettings(AppState state)
    {
        if (_settingsWindow is null)
        {
            _settingsWindow = new SettingsWindow(state);
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
            _settingsWindow.Show();
        }
        Bring(_settingsWindow);
    }

    private static void Bring(Window window)
    {
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Activate();
    }

    private void Quit() => Dispatcher.BeginInvoke(Shutdown, DispatcherPriority.Normal);
}
