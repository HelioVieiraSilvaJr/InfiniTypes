using InfiniTypes.App.Services;
using InfiniTypes.Core.Refinement;
using InfiniTypes.Core.Storage;

namespace InfiniTypes.App;

/// <summary>Preferências e glossário, gravados em JSON na pasta do app.</summary>
internal sealed class AppState
{
    private readonly JsonFileStore<AppSettings> _settingsStore = new(AppPaths.Settings);
    private readonly JsonFileStore<Glossary> _glossaryStore = new(AppPaths.Glossary);

    public AppSettings Settings { get; }
    public Glossary Glossary { get; }

    public AppState()
    {
        Settings = _settingsStore.Load();
        Glossary = _glossaryStore.Load();
    }

    public Effort Effort => EffortExtensions.ParseEffort(Settings.Effort);

    public void SaveSettings() => _settingsStore.Save(Settings);

    public void SaveGlossary() => _glossaryStore.Save(Glossary);
}
