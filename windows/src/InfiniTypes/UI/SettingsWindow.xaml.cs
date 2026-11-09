using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Navigation;
using InfiniTypes.App.Services;
using InfiniTypes.Core.Refinement;
using InfiniTypes.Core.Storage;

namespace InfiniTypes.App.UI;

/// <summary>Chave da API, modelo, glossário e abertura com o Windows.</summary>
public partial class SettingsWindow : Window
{
    private readonly AppState _state;
    private readonly ObservableCollection<GlossaryProject> _projects;
    private bool _loading = true;

    internal SettingsWindow(AppState state)
    {
        _state = state;
        InitializeComponent();
        _projects = new ObservableCollection<GlossaryProject>(state.Glossary.Projects);
        Projects.ItemsSource = _projects;
        GlobalTerms.Text = state.Glossary.GlobalTerms;
        LastWindow.Text = ContextCollector.LastWindowTitle is { } title ? $"Título da última janela: {title}" : "";
        EffortBox.ItemsSource = Enum.GetValues<Effort>().Select(e => e.Label()).ToList();
        EffortBox.SelectedIndex = (int)state.Effort;
        LaunchAtLogin.IsChecked = StartupRegistration.IsEnabled;
        ShowModels(ModelCatalog.Known);
        ShowKeyStatus();
        _loading = false;
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        SaveGlossary();
        base.OnClosing(e);
    }

    protected override void OnDeactivated(EventArgs e)
    {
        SaveGlossary();
        base.OnDeactivated(e);
    }

    // Chave da API

    private void SaveKey(object sender, RoutedEventArgs e)
    {
        var key = KeyBox.Password.Trim();
        if (key.Length == 0) return;
        try
        {
            CredentialStore.SetApiKey(key);
            KeyBox.Clear();
            ShowKeyStatus();
            RefreshModels(sender, e);
        }
        catch (Win32Exception error)
        {
            KeyStatus.Text = $"Não consegui salvar a chave: {error.Message}";
        }
    }

    private void RemoveKey(object sender, RoutedEventArgs e)
    {
        CredentialStore.SetApiKey(null);
        ShowKeyStatus();
    }

    private void ShowKeyStatus()
    {
        var key = CredentialStore.ApiKey();
        KeyStatus.Text = key is null
            ? "Nenhuma chave salva. Sem ela, o app cola só a transcrição, sem refinar."
            : $"Chave salva ({key[..Math.Min(10, key.Length)]}…{key[^Math.Min(4, key.Length)..]})";
        RemoveKeyButton.IsEnabled = key is not null;
    }

    // Modelo

    private async void RefreshModels(object sender, RoutedEventArgs e)
    {
        if (CredentialStore.ApiKey() is not { } key) return;
        try
        {
            var available = await new AnthropicClient(key).ListModelsAsync();
            ShowModels(ModelCatalog.Merge(available));
            PriceLabel.Text = $"{PriceLabel.Text} A conta tem {available.Count} modelos.".Trim();
        }
        catch (Exception error) when (error is AnthropicException or HttpRequestException)
        {
            PriceLabel.Text = $"Não consegui atualizar a lista: {error.Message}";
        }
    }

    private void ShowModels(IReadOnlyList<RefinementModel> models)
    {
        var wasLoading = _loading;
        _loading = true;
        var current = ModelCatalog.Model(_state.Settings.ModelId);
        var list = models.Any(m => m.Id == current.Id) ? models : [.. models, current];
        ModelBox.ItemsSource = list;
        ModelBox.SelectedItem = list.First(m => m.Id == current.Id);
        ShowModelDetails(current);
        _loading = wasLoading;
    }

    private void ModelChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || ModelBox.SelectedItem is not RefinementModel model) return;
        _state.Settings.ModelId = model.Id;
        _state.SaveSettings();
        ShowModelDetails(model);
    }

    private void ShowModelDetails(RefinementModel model)
    {
        PriceLabel.Text = model.PriceLabel ?? "Modelo sem preço conhecido: o app manda a requisição mínima, sem esforço.";
        EffortBox.IsEnabled = model.SupportsEffort;
    }

    private void EffortChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || EffortBox.SelectedIndex < 0) return;
        _state.Settings.Effort = ((Effort)EffortBox.SelectedIndex).RawValue();
        _state.SaveSettings();
    }

    // Glossário

    private void AddProject(object sender, RoutedEventArgs e) => _projects.Add(new GlossaryProject());

    private void RemoveProject(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: GlossaryProject project }) _projects.Remove(project);
        SaveGlossary();
    }

    private void SaveGlossary()
    {
        _state.Glossary.GlobalTerms = GlobalTerms.Text;
        _state.Glossary.Projects = [.. _projects];
        _state.SaveGlossary();
    }

    // Geral

    private void LaunchAtLoginChanged(object sender, RoutedEventArgs e)
    {
        var enabled = LaunchAtLogin.IsChecked == true;
        StartupRegistration.SetEnabled(enabled);
        _state.Settings.LaunchAtLogin = enabled;
        _state.SaveSettings();
    }

    private void OpenLink(object sender, RequestNavigateEventArgs e)
    {
        Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true });
        e.Handled = true;
    }
}
