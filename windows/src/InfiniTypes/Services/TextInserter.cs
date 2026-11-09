using System.Runtime.InteropServices;
using System.Windows;
using static InfiniTypes.App.Services.NativeMethods;

namespace InfiniTypes.App.Services;

/// <summary>Cola pela área de transferência e devolve depois o que estava nela.</summary>
internal static class TextInserter
{
    public static async Task PasteAsync(string text, string? processName)
    {
        var previous = ClipboardSnapshot.Take();
        if (!await SetTextAsync(text)) throw new InvalidOperationException("A área de transferência está ocupada por outro app");
        await Task.Delay(40);
        if (processName is not null && FocusDetector.ShiftInsertProcesses.Contains(processName))
            SendChord(VK_SHIFT, VK_INSERT, extended: true);
        else
            SendChord(VK_CONTROL, VK_V);
        // Dá tempo de o app ler a área de transferência antes de restaurá-la.
        await Task.Delay(500);
        if (ClipboardText() == text) previous.Restore();
    }

    public static Task<bool> CopyAsync(string text) => SetTextAsync(text);

    /// <summary>Simula Ctrl+C, por exemplo para ler a seleção quando a Automação da Interface não mostra.</summary>
    public static void SendCopy() => SendChord(VK_CONTROL, VK_C);

    public static string? ClipboardText()
    {
        try
        {
            return Clipboard.ContainsText() ? Clipboard.GetText() : null;
        }
        catch (COMException)
        {
            return null;
        }
    }

    /// <summary>Outro app pode estar com a área de transferência aberta; tenta algumas vezes.</summary>
    private static async Task<bool> SetTextAsync(string text)
    {
        for (var attempt = 0; attempt < 10; attempt++)
        {
            try
            {
                Clipboard.SetDataObject(new DataObject(DataFormats.UnicodeText, text), copy: true);
                return true;
            }
            catch (COMException)
            {
                await Task.Delay(30);
            }
        }
        return false;
    }

    private static void SendChord(int modifier, int key, bool extended = false)
    {
        var keyFlags = extended ? KEYEVENTF_EXTENDEDKEY : 0;
        INPUT[] inputs =
        [
            Key(modifier, 0),
            Key(key, keyFlags),
            Key(key, keyFlags | KEYEVENTF_KEYUP),
            Key(modifier, KEYEVENTF_KEYUP),
        ];
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT Key(int virtualKey, uint flags) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion { ki = new KEYBDINPUT { wVk = (ushort)virtualKey, dwFlags = flags } },
    };
}

/// <summary>Cópia de todos os formatos da área de transferência, para restaurá-la depois de colar.</summary>
internal sealed class ClipboardSnapshot
{
    private readonly DataObject? _data;

    private ClipboardSnapshot(DataObject? data) => _data = data;

    public static ClipboardSnapshot Take()
    {
        try
        {
            if (Clipboard.GetDataObject() is not { } source) return new(null);
            var copy = new DataObject();
            foreach (var format in source.GetFormats(autoConvert: false))
            {
                try
                {
                    if (source.GetData(format, autoConvert: false) is { } data) copy.SetData(format, data);
                }
                catch (Exception error) when (error is COMException or OutOfMemoryException or ExternalException)
                {
                    // Formatos que não se deixam copiar ficam de fora.
                }
            }
            return new(copy);
        }
        catch (COMException)
        {
            return new(null);
        }
    }

    public void Restore()
    {
        try
        {
            if (_data is null || _data.GetFormats().Length == 0) Clipboard.Clear();
            else Clipboard.SetDataObject(_data, copy: true);
        }
        catch (COMException)
        {
            // Se outro app pegou a área de transferência, o conteúdo dele vale mais.
        }
    }
}
