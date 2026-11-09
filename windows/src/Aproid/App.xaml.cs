using Aproid.Model;
using Aproid.Shell;
using Aproid.Views;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace Aproid;

/// Lives in the notification area: owns the tray icon, the panel and the app model.
public partial class App : Application
{
    private AppModel? model;
    private TrayIcon? tray;
    private PanelWindow? panel;
    private CallWindow? call;
    private MessagesWindow? messages;
    private PhotosWindow? photos;
    private ScreenWindow? screen;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Closing the panel only hides it; Aproid keeps running in the tray until Quit.
        DispatcherShutdownMode = DispatcherShutdownMode.OnExplicitShutdown;

        var ui = DispatcherQueue.GetForCurrentThread();
        model = new AppModel(ui);
        panel = new PanelWindow(model);
        tray = new TrayIcon(AppPaths.TrayIcon, "Aproid");

        tray.Clicked += () => panel.Toggle(tray.Bounds);
        tray.MenuRequested += ShowTrayMenu;
        tray.ClipboardChanged += model.ClipboardChanged;
        model.PairRequested += () => panel.ShowNear(tray.Bounds);
        panel.QuitRequested += Quit;
        call = new CallWindow(model);
        model.MessagesRequested += number => (messages ??= new MessagesWindow(model)).Present(number);
        model.DialerRequested += () => (messages ??= new MessagesWindow(model)).Present(dial: true);
        model.MirrorRequested += () => (screen ??= new ScreenWindow(model.Mirror)).Present();
        model.ScreenStarted += source =>
        {
            screen ??= new ScreenWindow(model.Mirror);
            screen.Play(source);
            screen.Present();
        };
        model.PhotosRequested += () => (photos ??= new PhotosWindow(model.Photos)).Present();

        // A second launch, such as from the Start menu, Explorer's "Send to phone" or a tel: link, comes here.
        AppInstance.GetCurrent().Activated += (_, activation) =>
        {
            var launch = activation.Data is Windows.ApplicationModel.Activation.ILaunchActivatedEventArgs data
                ? LaunchArguments.Parse(data.Arguments ?? "")
                : new LaunchArguments([], null, false);
            ui.TryEnqueue(() => Handle(launch));
        };

        Integration.Register();
        model.Start();

        var first = LaunchArguments.Parse(Environment.GetCommandLineArgs().Skip(1));
        if (!first.IsEmpty) Handle(first);
        else if (!first.Background) panel.ShowNear(tray.Bounds);
    }

    /// Sends files or calls a number handed over by Windows, or just opens the panel.
    private void Handle(LaunchArguments launch)
    {
        if (launch.IsEmpty)
        {
            panel!.ShowNear(tray!.Bounds);
            return;
        }

        model!.Handover(launch.Files, launch.Number);

        // The panel shows the files going across.
        if (launch.Files.Count > 0) panel!.ShowNear(tray!.Bounds);
    }

    private void ShowTrayMenu()
    {
        switch (tray!.ShowMenu(["Open Aproid", "Messages", "Photos", "Open Downloads", null, "Quit Aproid"]))
        {
            case 0:
                panel!.ShowNear(tray.Bounds);
                break;
            case 1:
                model!.ShowMessages();
                break;
            case 2:
                model!.ShowPhotos();
                break;
            case 3:
                Explorer.Open(AppPaths.Downloads);
                break;
            case 5:
                Quit();
                break;
        }
    }

    private void Quit()
    {
        model?.Stop();
        tray?.Dispose();
        panel?.Shutdown();
        call?.Close();
        messages?.Close();
        photos?.Close();
        screen?.Close();
        Exit();
    }
}
