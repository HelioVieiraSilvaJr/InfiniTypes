using System.Windows.Automation;

namespace InfiniTypes.App.Services;

internal enum FocusKind
{
    Editable,
    NotEditable,
    /// <summary>A Automação da Interface não diz: o app cola mesmo assim, como no Mac.</summary>
    Unknown,
}

/// <summary>Decide se há onde colar, pela Automação da Interface (UI Automation) do elemento em foco.</summary>
internal static class FocusDetector
{
    /// <summary>Terminais: sempre aceitam colar, mas colar não substitui a seleção.</summary>
    public static readonly HashSet<string> TerminalProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "WindowsTerminal", "OpenConsole", "conhost", "cmd", "powershell", "pwsh", "mintty", "alacritty",
        "wezterm-gui", "Hyper", "Tabby", "WarpTerminal",
    };

    /// <summary>O mintty (Git Bash) cola com Shift+Insert; os outros, com Ctrl+V.</summary>
    public static readonly HashSet<string> ShiftInsertProcesses = new(StringComparer.OrdinalIgnoreCase) { "mintty" };

    public static bool IsTerminal(string? processName) => processName is not null && TerminalProcesses.Contains(processName);

    public static async Task<FocusKind> CheckAsync(string? processName)
    {
        if (IsTerminal(processName)) return FocusKind.Editable;
        // A Automação da Interface pode travar em apps que não respondem: fica fora da thread da interface e com prazo.
        var check = Task.Run(Classify);
        return await Task.WhenAny(check, Task.Delay(400)) == check ? check.Result : FocusKind.Unknown;
    }

    private static FocusKind Classify()
    {
        try
        {
            var element = AutomationElement.FocusedElement;
            if (element is null) return FocusKind.Unknown;
            var type = element.Current.ControlType;
            if (type == ControlType.Edit || type == ControlType.Document) return FocusKind.Editable;
            if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var value) && !((ValuePattern)value).Current.IsReadOnly)
                return FocusKind.Editable;
            // Área de trabalho e listas do Explorador de Arquivos: não há onde digitar.
            var isExplorer = string.Equals(ProcessName(element), "explorer", StringComparison.OrdinalIgnoreCase);
            if (isExplorer && (type == ControlType.List || type == ControlType.ListItem || type == ControlType.Tree
                    || type == ControlType.TreeItem || type == ControlType.Pane))
                return FocusKind.NotEditable;
            return FocusKind.Unknown;
        }
        catch (Exception error) when (error is ElementNotAvailableException or InvalidOperationException
                                          or System.Runtime.InteropServices.COMException)
        {
            return FocusKind.Unknown;
        }
    }

    private static string? ProcessName(AutomationElement element)
    {
        try
        {
            using var process = System.Diagnostics.Process.GetProcessById(element.Current.ProcessId);
            return process.ProcessName;
        }
        catch (ArgumentException)
        {
            return null;
        }
    }
}
