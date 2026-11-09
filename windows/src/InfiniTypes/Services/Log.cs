namespace InfiniTypes.App.Services;

/// <summary>
/// Log em <c>%LOCALAPPDATA%\InfiniTypes\Logs\InfiniTypes.log</c>. Registra etapas, tempos e erros, nunca o texto ditado.
/// </summary>
internal static class Log
{
    private const long MaxBytes = 1_000_000;
    private static readonly Lock Gate = new();
    private static readonly string FilePath = Path.Combine(AppPaths.Logs, "InfiniTypes.log");

    public static void Info(string message) => Write("INFO", message);

    public static void Error(string message) => Write("ERRO", message);

    private static void Write(string level, string message)
    {
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(AppPaths.Logs);
                if (File.Exists(FilePath) && new FileInfo(FilePath).Length > MaxBytes)
                    File.Move(FilePath, FilePath + ".1", overwrite: true);
                File.AppendAllText(FilePath, $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff} {level} {message}{Environment.NewLine}");
            }
            catch (IOException)
            {
                // Sem log o app continua funcionando.
            }
        }
    }
}

internal static class AppPaths
{
    /// <summary><c>%LOCALAPPDATA%\InfiniTypes</c>: histórico, preferências, glossário, modelo de voz e logs.</summary>
    public static readonly string Root =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "InfiniTypes");

    public static string Logs => Path.Combine(Root, "Logs");
    public static string Models => Path.Combine(Root, "Models");
    public static string History => Path.Combine(Root, "History.db");
    public static string Settings => Path.Combine(Root, "Settings.json");
    public static string Glossary => Path.Combine(Root, "Glossary.json");
}
