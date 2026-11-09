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
        model.PhotosRequested += () => (photos ??= new PhotosWindow(model.Photos)).Present();

        // A second launch, such as from the Start menu, opens the panel of this one.
        AppInstance.GetCurrent().Activated += (_, _) => ui.TryEnqueue(() => panel.ShowNear(tray.Bounds));

        model.Start();

        if (!Environment.GetCommandLineArgs().Contains(Startup.BackgroundArgument)) panel.ShowNear(tray.Bounds);
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
        Exit();
    }
}
