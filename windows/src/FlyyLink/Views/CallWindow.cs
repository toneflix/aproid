using FlyyLink.Icons;
using FlyyLink.Model;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using WinRT.Interop;
using static FlyyLink.Shell.NativeMethods;

namespace FlyyLink.Views;

/// The call banner in the top right corner: who is calling with Answer and Decline, or the running call with Mute and Hang up.
public sealed class CallWindow : Window
{
    private const int CardWidth = 380;
    private const int CardHeight = 104;
    private const int Margin = 12;

    private readonly AppModel model;
    private readonly IntPtr hwnd;
    private readonly DispatcherQueueTimer clock;
    private readonly Avatar avatar = new() { Diameter = 48 };
    private readonly TextBlock title = new() { FontSize = 15, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock status = new() { FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly StackPanel buttons = new() { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
    private ActiveCall? shown;

    public CallWindow(AppModel model)
    {
        this.model = model;
        Title = "Call";
        SystemBackdrop = new DesktopAcrylicBackdrop();

        hwnd = WindowNative.GetWindowHandle(this);
        AppWindow.IsShownInSwitchers = false;
        AppWindow.SetIcon(AppPaths.WindowIcon);
        AppWindow.Closing += (_, args) => args.Cancel = true;

        var presenter = OverlappedPresenter.Create();
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.IsAlwaysOnTop = true;
        presenter.SetBorderAndTitleBar(true, false);
        AppWindow.SetPresenter(presenter);

        var round = DWMWCP_ROUND;
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref round, sizeof(int));

        status.SetValue(TextBlock.ForegroundProperty, Application.Current.Resources["FlyyLinkSubBrush"]);
        title.SetValue(TextBlock.ForegroundProperty, Application.Current.Resources["FlyyLinkTextBrush"]);

        var text = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center, Children = { title, status } };
        var row = new Grid { ColumnSpacing = 12, Padding = new Thickness(16, 0, 14, 0) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        avatar.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(text, 1);
        Grid.SetColumn(buttons, 2);
        row.Children.Add(avatar);
        row.Children.Add(text);
        row.Children.Add(buttons);
        Content = row;

        clock = DispatcherQueue.CreateTimer();
        clock.Interval = TimeSpan.FromSeconds(1);
        clock.Tick += (_, _) => ShowStatus();

        model.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(AppModel.Call)) Update();
        };
    }

    private void Update()
    {
        var call = model.Call;
        if (call is null)
        {
            shown = null;
            clock.Stop();
            AppWindow.Hide();
            return;
        }

        // Only rebuild the buttons when the phase or mute changes, so a click is never lost mid-press.
        if (shown is null || shown.Phase != call.Phase || shown.IsMuted != call.IsMuted) Buttons(call);
        if (shown?.Title != call.Title || shown?.Photo != call.Photo)
        {
            avatar.NameText = call.Title;
            avatar.Photo = call.Photo;
            title.Text = call.Title;
        }

        var appearing = shown is null;
        shown = call;
        ShowStatus();
        clock.Start();

        if (appearing) Appear();
    }

    private void ShowStatus()
    {
        if (model.Call is ActiveCall call) status.Text = call.Status(DateTimeOffset.Now);
    }

    private void Buttons(ActiveCall call)
    {
        buttons.Children.Clear();

        if (call.IsRinging)
        {
            buttons.Children.Add(Round(Lucide.PhoneOff, "#E5484D", "Decline", model.DeclineCall));
            buttons.Children.Add(Round(Lucide.Phone, "#30A46C", $"Answer on {call.DeviceName}", model.AnswerCall));
            return;
        }

        buttons.Children.Add(Round(call.IsMuted ? Lucide.MicOff : Lucide.Mic, null, call.IsMuted ? "Unmute" : "Mute", model.ToggleMute, call.IsMuted));
        buttons.Children.Add(Round(Lucide.PhoneOff, "#E5484D", "Hang up", model.HangUp));
    }

    /// A round button: coloured for answer and hang up, grey otherwise, inverted while switched on.
    private static Button Round(Lucide icon, string? color, string label, Action action, bool on = false)
    {
        var glyph = new LucideIcon { Icon = icon, Size = 16 };
        var button = new Button
        {
            Width = 40,
            Height = 40,
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(20),
            BorderThickness = new Thickness(0),
            Content = glyph,
        };

        if (color is not null)
        {
            button.Background = new SolidColorBrush(Geometries.Argb(0xFF000000 | Convert.ToUInt32(color[1..], 16)));
            glyph.Foreground = new SolidColorBrush(Colors.White);
        }
        else
        {
            button.SetValue(Control.BackgroundProperty, Application.Current.Resources[on ? "FlyyLinkTextBrush" : "FlyyLinkThumbBrush"]);
            glyph.SetValue(Control.ForegroundProperty, Application.Current.Resources[on ? "FlyyLinkCardBrush" : "FlyyLinkTextBrush"]);
        }

        button.Click += (_, _) => action();
        ToolTipService.SetToolTip(button, label);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, label);

        return button;
    }

    /// Shows the card in the top right corner of the main screen without taking focus from what the user is doing.
    private void Appear()
    {
        var scale = GetDpiForWindow(hwnd) / 96.0;
        var work = DisplayArea.Primary.WorkArea;
        var width = (int)(CardWidth * scale);
        var height = (int)(CardHeight * scale);
        var margin = (int)(Margin * scale);

        AppWindow.MoveAndResize(new RectInt32(work.X + work.Width - width - margin, work.Y + margin, width, height));
        AppWindow.Show(false);
    }
}
