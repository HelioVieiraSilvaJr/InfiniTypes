using System.Globalization;

namespace InfiniTypes.Core.Storage;

/// <summary>Título das seções do histórico: "Hoje", "Ontem" ou a data por extenso.</summary>
public static class DayGrouping
{
    private static readonly CultureInfo Portuguese = CultureInfo.GetCultureInfo("pt-BR");

    public static string Title(DateTime day, DateTime today)
    {
        var date = day.Date;
        if (date == today.Date) return "Hoje";
        if (date == today.Date.AddDays(-1)) return "Ontem";
        return date.ToString("d 'de' MMMM 'de' yyyy", Portuguese);
    }
}
