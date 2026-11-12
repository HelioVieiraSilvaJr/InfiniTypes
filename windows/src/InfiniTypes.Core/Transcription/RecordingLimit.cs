namespace InfiniTypes.Core.Transcription;

/// <summary>Tempo máximo de uma gravação e a contagem regressiva mostrada enquanto ela dura.</summary>
public static class RecordingLimit
{
    /// <summary>Tempo para desenvolver uma ideia longa. Ao chegar nele, a gravação termina e o ditado segue normalmente.</summary>
    public static readonly TimeSpan Duration = TimeSpan.FromMinutes(10);

    /// <summary>Tempo restante como "10:00", "9:59", …, "0:00". Arredonda para cima, para começar no limite cheio.</summary>
    public static string RemainingLabel(TimeSpan elapsed)
    {
        var remaining = Math.Max(0, (int)Math.Ceiling((Duration - elapsed).TotalSeconds));
        return $"{remaining / 60}:{remaining % 60:00}";
    }
}
