using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using static InfiniTypes.App.Services.NativeMethods;

namespace InfiniTypes.App.UI;

/// <summary>
/// Aviso flutuante no rodapé da tela: gravando, trabalhando ou o resultado. Não recebe foco nem cliques,
/// para nunca tirar o cursor do campo onde o texto vai ser colado.
/// </summary>
public partial class HudWindow : Window
{
    private static readonly Brush Blue = Frozen(0x4F, 0x8C, 0xFF);
    private static readonly Brush Red = Frozen(0xFF, 0x5A, 0x5A);
    private static readonly Brush Green = Frozen(0x3D, 0xD6, 0x8C);
    private static readonly Brush Amber = Frozen(0xFF, 0xC1, 0x4D);
    private static readonly Brush Gray = Frozen(0xA0, 0xA0, 0xA8);

    private readonly DispatcherTimer _refresh = new() { Interval = TimeSpan.FromMilliseconds(60) };
    private readonly DispatcherTimer _hide = new();
    private Func<float>? _level;
    private Func<string?>? _detail;
    private Func<string>? _countdown;
    private string _message = "";

    public HudWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            var style = GetWindowLongPtr(handle, GWL_EXSTYLE).ToInt64();
            SetWindowLongPtr(handle, GWL_EXSTYLE, new IntPtr(style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT));
        };
        SizeChanged += (_, _) => Reposition();
        _refresh.Tick += (_, _) => Refresh();
        _hide.Tick += (_, _) => HideNow();
    }

    /// <param name="countdown">Tempo que falta para a gravação terminar sozinha, como "9:59".</param>
    public void ShowRecording(string message, Func<float> level, Func<string> countdown) =>
        Present(message, Red, level: level, countdown: countdown);

    /// <param name="detail">Texto que substitui a mensagem enquanto não for nulo, como o progresso de um download.</param>
    public void ShowWorking(string message, Func<string?>? detail = null) => Present(message, Blue, detail: detail);

    public void ShowSuccess(string message) => Present(message, Green, hideAfter: TimeSpan.FromSeconds(2.5));

    public void ShowNotice(string message) => Present(message, Gray, hideAfter: TimeSpan.FromSeconds(4));

    public void ShowFailure(string message) => Present(message, Amber, hideAfter: TimeSpan.FromSeconds(7));

    public void HideNow()
    {
        _refresh.Stop();
        _hide.Stop();
        _level = null;
        _detail = null;
        _countdown = null;
        Hide();
    }

    private void Present(string message, Brush color, Func<float>? level = null, Func<string?>? detail = null,
        Func<string>? countdown = null, TimeSpan? hideAfter = null)
    {
        _message = message;
        _level = level;
        _detail = detail;
        _countdown = countdown;
        Countdown.Text = countdown?.Invoke() ?? "";
        Countdown.Visibility = countdown is null ? Visibility.Collapsed : Visibility.Visible;
        Message.Text = message;
        Indicator.Fill = color;
        LevelBar.Background = color;
        LevelTrack.Visibility = level is null ? Visibility.Collapsed : Visibility.Visible;
        _hide.Stop();
        if (hideAfter is { } delay)
        {
            _hide.Interval = delay;
            _hide.Start();
        }
        if (level is not null || detail is not null || countdown is not null) _refresh.Start();
        else _refresh.Stop();
        if (!IsVisible) Show();
        Reposition();
    }

    private void Refresh()
    {
        if (_level is { } level) LevelBar.Width = LevelTrack.Width * Math.Clamp(level(), 0, 1);
        if (_detail is not null) Message.Text = _detail() ?? _message;
        if (_countdown is { } countdown) Countdown.Text = countdown();
    }

    /// <summary>Centralizado, logo acima da barra de tarefas do monitor principal.</summary>
    private void Reposition()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - ActualWidth) / 2;
        Top = area.Bottom - ActualHeight - 24;
    }

    private static SolidColorBrush Frozen(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }
}
