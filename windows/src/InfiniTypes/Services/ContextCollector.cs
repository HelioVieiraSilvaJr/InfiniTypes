using System.Diagnostics;
using InfiniTypes.Core;

namespace InfiniTypes.App.Services;

/// <summary>App e janela em foco, para o refinamento acertar nomes e escolher o projeto do glossário.</summary>
internal static class ContextCollector
{
    /// <summary>Título da última janela capturada, mostrado nas preferências para ajudar a dar nome aos projetos.</summary>
    public static string? LastWindowTitle { get; private set; }

    public static DictationContext Capture()
    {
        var window = NativeMethods.GetForegroundWindow();
        if (window == IntPtr.Zero) return DictationContext.Empty;
        var title = NativeMethods.WindowTitle(window);
        NativeMethods.GetWindowThreadProcessId(window, out var processId);
        var (name, id) = Describe(processId);
        LastWindowTitle = title.Length > 0 ? title : LastWindowTitle;
        return new DictationContext(name, id, title.Length > 0 ? title : null);
    }

    /// <summary>Nome de exibição do app (ex.: "Visual Studio Code") e o nome do processo (ex.: "Code").</summary>
    private static (string? Name, string? Id) Describe(uint processId)
    {
        try
        {
            using var process = Process.GetProcessById((int)processId);
            var id = process.ProcessName;
            try
            {
                var description = process.MainModule?.FileVersionInfo.FileDescription;
                return (string.IsNullOrWhiteSpace(description) ? id : description.Trim(), id);
            }
            catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
            {
                // Processos elevados não deixam ler o módulo; o nome do processo basta.
                return (id, id);
            }
        }
        catch (ArgumentException)
        {
            return (null, null);
        }
    }
}
