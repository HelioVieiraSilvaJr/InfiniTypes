using System.Windows;
using Forms = System.Windows.Forms;

namespace InfiniTypes.App.UI;

/// <summary>Ícone na área de notificação: o app não tem janela principal.</summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly Forms.NotifyIcon _icon;

    public TrayIcon(Action openHistory, Action openSettings, Action quit)
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Histórico", null, (_, _) => openHistory());
        menu.Items.Add("Preferências…", null, (_, _) => openSettings());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Sair do InfiniTypes", null, (_, _) => quit());

        using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/InfiniTypes.ico"))!.Stream;
        _icon = new Forms.NotifyIcon
        {
            Icon = new System.Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize),
            Text = "InfiniTypes: segure o Ctrl direito para ditar",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _icon.MouseClick += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) openHistory();
        };
    }

    public void ShowTip(string title, string text) => _icon.ShowBalloonTip(5000, title, text, Forms.ToolTipIcon.None);

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
