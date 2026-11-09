using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace Aproid;

/// Starts the app, or hands over to the copy that is already running so there is only ever one tray icon.
public static class Program
{
    [STAThread]
    private static int Main()
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();

        if (RedirectToRunningInstance()) return 0;

        Application.Start(callback =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            new App();
        });

        return 0;
    }

    private static bool RedirectToRunningInstance()
    {
        var main = AppInstance.FindOrRegisterForKey("aproid");
        if (main.IsCurrent) return false;

        // The redirect is a cross-process call, so wait for it without blocking this thread's COM messages.
        var args = AppInstance.GetCurrent().GetActivatedEventArgs();
        var done = CreateEvent(IntPtr.Zero, true, false, null);
        Task.Run(() =>
        {
            main.RedirectActivationToAsync(args).AsTask().Wait();
            SetEvent(done);
        });
        CoWaitForMultipleObjects(0, 0xFFFFFFFF, 1, [done], out _);

        return true;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateEvent(IntPtr attributes, bool manualReset, bool initialState, string? name);

    [DllImport("kernel32.dll")]
    private static extern bool SetEvent(IntPtr handle);

    [DllImport("ole32.dll")]
    private static extern uint CoWaitForMultipleObjects(uint flags, uint milliseconds, uint count, IntPtr[] handles, out uint index);
}
