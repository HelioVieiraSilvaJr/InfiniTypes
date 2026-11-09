using System.Text.Encodings.Web;
using System.Text.Json;
using InfiniTypes.Core.Refinement;

namespace InfiniTypes.Core.Storage;

/// <summary>Preferências do app. A chave da API não fica aqui: vai para o cofre de credenciais do sistema.</summary>
public sealed class AppSettings
{
    public string ModelId { get; set; } = ModelCatalog.DefaultModelId;
    public string Effort { get; set; } = "low";
    public bool LaunchAtLogin { get; set; }
}

/// <summary>Lê e grava um objeto em JSON. Um arquivo ilegível volta ao padrão, sem derrubar o app.</summary>
public sealed class JsonFileStore<T>(string path) where T : class, new()
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public string Path { get; } = path;

    public T Load()
    {
        try
        {
            return File.Exists(Path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(Path), Options) ?? new T() : new T();
        }
        catch (JsonException)
        {
            return new T();
        }
    }

    public void Save(T value)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path))!);
        var temporary = Path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(value, Options));
        File.Move(temporary, Path, overwrite: true);
    }
}
