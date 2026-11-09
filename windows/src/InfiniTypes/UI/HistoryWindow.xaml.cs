using System.Diagnostics;
using System.Windows;
using System.Windows.Data;
using InfiniTypes.App.Services;
using InfiniTypes.Core;
using InfiniTypes.Core.Refinement;
using InfiniTypes.Core.Storage;

namespace InfiniTypes.App.UI;

/// <summary>Todo ditado fica aqui, para você nunca perder o que falou.</summary>
public partial class HistoryWindow : Window
{
    private readonly HistoryStore _history;

    internal HistoryWindow(HistoryStore history)
    {
        _history = history;
        InitializeComponent();
        _history.Changed += Reload;
        Closed += (_, _) => _history.Changed -= Reload;
        Reload();
    }

    private void Reload()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(Reload);
            return;
        }
        var today = DateTime.Now;
        var items = _history.Records(Search.Text).Select(r => new RecordItem(r, today)).ToList();
        var view = new ListCollectionView(items);
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(RecordItem.Day)));
        Records.ItemsSource = view;
        var marked = _history.EvalSet().Count;
        Summary.Text = $"{items.Count} ditados{(string.IsNullOrWhiteSpace(Search.Text) ? "" : " encontrados")} · {marked} marcados para a avaliação";
        ExportButton.IsEnabled = marked > 0;
    }

    private void SearchChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) => Reload();

    private async void Copy(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: RecordItem item }) await TextInserter.CopyAsync(item.Record.Text);
    }

    private void ToggleStar(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: RecordItem item }) return;
        item.Record.InEvalSet = !item.Record.InEvalSet;
        _history.Update(item.Record);
    }

    private void Delete(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: RecordItem item }) return;
        var answer = MessageBox.Show(this, "Excluir este ditado do histórico? Não dá para desfazer.", "InfiniTypes",
            MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (answer == MessageBoxResult.Yes) _history.Delete(item.Record.Id);
    }

    private void Export(object sender, RoutedEventArgs e)
    {
        var path = EvalExporter.Export(_history.EvalSet(), AppPaths.Root);
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
    }

    private void OpenFolder(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{AppPaths.Root}\"") { UseShellExecute = true });
}

/// <summary>Um ditado como aparece na lista.</summary>
internal sealed class RecordItem(DictationRecord record, DateTime today)
{
    public DictationRecord Record { get; } = record;

    public string Day { get; } = DayGrouping.Title(record.CreatedAt.LocalDateTime, today);

    public string Text => Record.Text;

    public string Star => Record.InEvalSet ? "★" : "☆";

    public string Header
    {
        get
        {
            var parts = new List<string> { Record.CreatedAt.LocalDateTime.ToString("HH:mm"), Record.Mode.Label() };
            if (Record.AppName is { } app) parts.Add(app);
            if (Record.ProjectName is { } project) parts.Add(project);
            if (Record.ModelId is { } model) parts.Add(ModelCatalog.Model(model).DisplayName);
            return string.Join(" · ", parts);
        }
    }

    public string Status => Record switch
    {
        { ErrorMessage: { } error } => Record.Refined ? error : $"Sem refinar: {error}",
        { Pasted: false } => "Não foi colado: está só aqui no histórico",
        _ => "",
    };

    public Visibility StatusVisibility => Status.Length == 0 ? Visibility.Collapsed : Visibility.Visible;

    public string Details
    {
        get
        {
            var lines = new List<string> { $"Transcrição: {Record.RawTranscript}" };
            if (Record.OriginalText is { } original) lines.Add($"Texto original: {original}");
            lines.Add($"Áudio {Record.AudioSeconds:F1} s · transcrição {Record.TranscriptionSeconds:F1} s" +
                      (Record.RefinementSeconds is { } refinement ? $" · refinamento {refinement:F1} s" : ""));
            return string.Join("\n\n", lines);
        }
    }
}
