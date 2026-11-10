using Aproid.Model;

namespace Aproid.Shell;

/// Writes unhandled errors to %LOCALAPPDATA%\Aproid\crash.log, newest last, so a crash can be traced.
internal static class CrashLog
{
    private const long MaxSize = 256 * 1024;

    public static string Path => System.IO.Path.Combine(AppPaths.Data, "crash.log");

    public static void Attach(Microsoft.UI.Xaml.Application app)
    {
        app.UnhandledException += (_, args) => Write("UI", args.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, args) => Write("Process", args.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, args) => Write("Task", args.Exception);
    }

    private static void Write(string source, Exception? error)
    {
        try
        {
            if (File.Exists(Path) && new FileInfo(Path).Length > MaxSize) File.Delete(Path);

            File.AppendAllText(Path, $"[{DateTimeOffset.Now:u}] {source} {Updater.CurrentText}\n{error}\n\n");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
        }
    }
}
