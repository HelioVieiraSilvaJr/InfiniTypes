using System.Windows.Automation;
using System.Windows.Automation.Text;

namespace InfiniTypes.App.Services;

internal abstract record Selection
{
    public sealed record None : Selection;
    public sealed record Text(string Value) : Selection;
    /// <summary>Campo de senha: o conteúdo nunca é lido.</summary>
    public sealed record SecureField : Selection;

    public static readonly Selection Nothing = new None();
}

/// <summary>Lê o texto selecionado no app em foco, para a revisão por voz.</summary>
internal static class SelectionReader
{
    /// <summary>Pela Automação da Interface (<c>TextPattern</c>), sem mexer na área de transferência.</summary>
    public static async Task<Selection> AutomationSelectionAsync()
    {
        var read = Task.Run(Read);
        return await Task.WhenAny(read, Task.Delay(300)) == read ? read.Result : Selection.Nothing;
    }

    /// <summary>Reserva: simula Ctrl+C e lê a área de transferência, restaurando-a depois.</summary>
    public static async Task<Selection> CopySelectionAsync(TimeSpan timeout)
    {
        var previous = ClipboardSnapshot.Take();
        var before = TextInserter.ClipboardText();
        try
        {
            System.Windows.Clipboard.Clear();
        }
        catch (System.Runtime.InteropServices.COMException)
        {
            return Selection.Nothing;
        }
        TextInserter.SendCopy();
        var deadline = DateTime.UtcNow + timeout;
        string? copied = null;
        while (DateTime.UtcNow < deadline)
        {
            await Task.Delay(40);
            copied = TextInserter.ClipboardText();
            if (!string.IsNullOrEmpty(copied)) break;
        }
        previous.Restore();
        // Sem seleção, alguns apps copiam a linha inteira; o mesmo texto de antes também não conta.
        return string.IsNullOrEmpty(copied) || copied == before ? Selection.Nothing : new Selection.Text(copied);
    }

    private static Selection Read()
    {
        try
        {
            var element = AutomationElement.FocusedElement;
            if (element is null) return Selection.Nothing;
            if (element.Current.IsPassword) return new Selection.SecureField();
            if (!element.TryGetCurrentPattern(TextPattern.Pattern, out var pattern)) return Selection.Nothing;
            var ranges = ((TextPattern)pattern).GetSelection();
            var text = string.Concat(ranges.Select(range => range.GetText(-1)));
            return text.Length == 0 ? Selection.Nothing : new Selection.Text(text);
        }
        catch (Exception error) when (error is ElementNotAvailableException or InvalidOperationException
                                          or System.Runtime.InteropServices.COMException)
        {
            return Selection.Nothing;
        }
    }
}
