namespace InfiniTypes.Core.Input;

public enum HotkeyEventKind
{
    Press,
    /// <summary>Ditado de prompt sem segurar a tecla: termina com um toque no atalho, e o Esc cancela.</summary>
    HandsFree,
    Release,
    Cancel,
}

public readonly record struct HotkeyEvent(HotkeyEventKind Kind, DictationMode Mode = DictationMode.Prompt)
{
    public static HotkeyEvent Press(DictationMode mode) => new(HotkeyEventKind.Press, mode);
    public static readonly HotkeyEvent HandsFree = new(HotkeyEventKind.HandsFree);
    public static readonly HotkeyEvent Release = new(HotkeyEventKind.Release);
    public static readonly HotkeyEvent Cancel = new(HotkeyEventKind.Cancel);
}

/// <summary>Tecla que dispara o ditado. <paramref name="DoubleTapMode"/> vale quando ela é segurada logo depois de um toque rápido.</summary>
/// <param name="DoubleTapStartsHandsFree">Dois toques rápidos começam o ditado mãos-livres, em vez do modo da tecla.</param>
public sealed record HotkeyTrigger(
    int VirtualKey,
    DictationMode Mode,
    DictationMode? DoubleTapMode = null,
    bool DoubleTapStartsHandsFree = false);

/// <summary>
/// Regras do atalho, separadas do gancho de teclado para poderem ser testadas.
/// </summary>
/// <remarks>
/// O ditado começa quando só a tecla do atalho está pressionada. Qualquer outra tecla enquanto ela está
/// segurada indica um atalho comum (ex.: Ctrl+C), e o ditado é cancelado. No Windows a tecla segurada se
/// repete (auto-repeat), então as repetições da própria tecla são ignoradas.
/// </remarks>
public sealed class HotkeyLogic(IReadOnlyList<HotkeyTrigger> triggers, double doubleTapWindow = 0.5)
{
    public const int RightControl = 0xA3;
    public const int RightShift = 0xA1;
    public const int Escape = 0x1B;

    /// <summary>Ctrl direito: prompt; toque rápido e segurar: revisão. Shift direito: literal; dois toques: mãos-livres.</summary>
    /// <remarks>O Alt direito fica de fora: no teclado ABNT2 ele é o AltGr, usado para digitar / ? °.</remarks>
    public static readonly IReadOnlyList<HotkeyTrigger> DefaultTriggers =
    [
        new(RightControl, DictationMode.Prompt, DictationMode.Revision),
        new(RightShift, DictationMode.Literal, DoubleTapStartsHandsFree: true),
    ];

    /// <summary>Um toque dura no máximo isto…</summary>
    public const double TapMaxDuration = 0.4;

    /// <summary>…e a segunda pressão precisa vir até este tempo depois de soltar.</summary>
    public double DoubleTapWindow { get; } = doubleTapWindow;

    private HotkeyTrigger? _holding;
    private double _pressedAt;
    private bool _interrupted;
    private (int Key, double EndedAt)? _lastTap;
    /// <summary>A tecla segurada pode encerrar o mãos-livres, se for solta sem outra tecla no meio.</summary>
    private bool _endingHandsFree;

    /// <summary>Gravando no modo mãos-livres, sem a tecla segurada.</summary>
    public bool IsHandsFree { get; private set; }

    public HotkeyLogic() : this(DefaultTriggers) { }

    /// <param name="otherModifiersDown">Se Ctrl, Shift, Alt ou Win (exceto a própria tecla) estão pressionados.</param>
    /// <param name="time">Instante do evento, em segundos.</param>
    public HotkeyEvent? KeyDown(int virtualKey, bool otherModifiersDown, double time)
    {
        if (_holding is { } holding)
        {
            // Repetição automática da tecla segurada.
            if (virtualKey == holding.VirtualKey) return null;
            return Interrupt();
        }

        var trigger = triggers.FirstOrDefault(t => t.VirtualKey == virtualKey);
        if (IsHandsFree && trigger is null)
        {
            // No mãos-livres, só o Esc cancela: dá para digitar e usar atalhos enquanto fala.
            _lastTap = null;
            if (virtualKey != Escape) return null;
            IsHandsFree = false;
            return HotkeyEvent.Cancel;
        }
        if (trigger is null || otherModifiersDown)
        {
            _lastTap = null;
            return null;
        }
        var isDoubleTap = _lastTap is { } tap && tap.Key == virtualKey && time - tap.EndedAt <= DoubleTapWindow;
        _holding = trigger;
        _pressedAt = time;
        _interrupted = false;
        _lastTap = null;
        if (IsHandsFree)
        {
            // Só um toque isolado termina o mãos-livres: Shift direito + letra (uma maiúscula) não.
            _endingHandsFree = true;
            return null;
        }
        if (isDoubleTap && trigger.DoubleTapStartsHandsFree)
        {
            IsHandsFree = true;
            _interrupted = true;
            return HotkeyEvent.HandsFree;
        }
        return HotkeyEvent.Press(isDoubleTap ? trigger.DoubleTapMode ?? trigger.Mode : trigger.Mode);
    }

    public HotkeyEvent? KeyUp(int virtualKey, double time)
    {
        if (_holding is not { } holding || virtualKey != holding.VirtualKey) return null;
        _holding = null;
        if (_endingHandsFree)
        {
            _endingHandsFree = false;
            if (_interrupted) return null;
            IsHandsFree = false;
            return HotkeyEvent.Release;
        }
        var wasTap = !_interrupted && time - _pressedAt <= TapMaxDuration;
        _lastTap = wasTap ? (virtualKey, time) : null;
        return _interrupted ? null : HotkeyEvent.Release;
    }

    /// <summary>O ditado mãos-livres terminou por outro caminho (tempo máximo, falha): o próximo toque começa um novo.</summary>
    public void EndHandsFree() => IsHandsFree = false;

    private HotkeyEvent? Interrupt()
    {
        if (_interrupted) return null;
        _interrupted = true;
        return _endingHandsFree ? null : HotkeyEvent.Cancel;
    }
}
