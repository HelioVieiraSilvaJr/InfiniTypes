using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using InfiniTypes.Core;
using InfiniTypes.Core.Input;
using static InfiniTypes.App.Services.NativeMethods;

namespace InfiniTypes.App.Services;

/// <summary>
/// Gancho de teclado de baixo nível (<c>WH_KEYBOARD_LL</c>): vê o atalho em qualquer app, sem impedir a tecla
/// de chegar a ele. Roda na thread da interface, que já tem o laço de mensagens que o gancho exige.
/// </summary>
internal sealed class KeyboardHook : IDisposable
{
    private static readonly int[] Modifiers =
        [VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN];

    private readonly HotkeyLogic _logic;
    private readonly Dispatcher _dispatcher;
    // Mantém o delegate vivo enquanto o gancho existir: o Windows guarda só o ponteiro.
    private readonly LowLevelKeyboardProc _callback;
    private IntPtr _hook;

    public event Action<DictationMode>? Pressed;
    public event Action? HandsFreeStarted;
    public event Action? Released;
    public event Action? Cancelled;

    public KeyboardHook(Dispatcher dispatcher)
    {
        _dispatcher = dispatcher;
        // O toque duplo segue o intervalo de clique duplo do sistema, dentro de limites confortáveis.
        _logic = new HotkeyLogic(HotkeyLogic.DefaultTriggers, Math.Clamp(GetDoubleClickTime() / 1000.0, 0.5, 0.8));
        _callback = Callback;
    }

    public void Start()
    {
        if (_hook != IntPtr.Zero) return;
        _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _callback, GetModuleHandle(null), 0);
        if (_hook == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    /// <summary>O ditado mãos-livres terminou por outro caminho (tempo máximo, falha).</summary>
    public void EndHandsFree() => _logic.EndHandsFree();

    public void Dispose()
    {
        if (_hook == IntPtr.Zero) return;
        UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }

    private IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            // As teclas que o próprio app simula (Ctrl+V, Ctrl+C) não contam.
            if ((data.flags & LLKHF_INJECTED) == 0) Handle((int)wParam, (int)data.vkCode);
        }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private void Handle(int message, int virtualKey)
    {
        var time = Environment.TickCount64 / 1000.0;
        HotkeyEvent? result = message switch
        {
            WM_KEYDOWN or WM_SYSKEYDOWN => _logic.KeyDown(virtualKey, OtherModifiersDown(virtualKey), time),
            WM_KEYUP or WM_SYSKEYUP => _logic.KeyUp(virtualKey, time),
            _ => null,
        };
        if (result is not { } hotkey) return;
        // O gancho precisa devolver rápido; o trabalho vai para a fila da interface.
        _dispatcher.BeginInvoke(() =>
        {
            switch (hotkey.Kind)
            {
                case HotkeyEventKind.Press:
                    Log.Info($"Atalho → {hotkey.Mode.RawValue()}");
                    Pressed?.Invoke(hotkey.Mode);
                    break;
                case HotkeyEventKind.HandsFree:
                    Log.Info("Atalho → mãos-livres");
                    HandsFreeStarted?.Invoke();
                    break;
                case HotkeyEventKind.Release:
                    Released?.Invoke();
                    break;
                case HotkeyEventKind.Cancel:
                    Cancelled?.Invoke();
                    break;
            }
        });
    }

    private static bool OtherModifiersDown(int virtualKey) =>
        Modifiers.Any(modifier => modifier != virtualKey && IsDown(modifier));
}
