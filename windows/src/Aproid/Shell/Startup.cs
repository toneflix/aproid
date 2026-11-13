using Microsoft.Win32;

namespace Aproid.Shell;

/// Starting FlyyLink when the user signs in, through the per-user Run key.
internal static class Startup
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "Aproid";

    /// Passed when Windows starts FlyyLink, so it stays in the tray instead of opening the panel.
    public const string BackgroundArgument = "--background";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);

            return key?.GetValue(Name) is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) key.SetValue(Name, $"\"{Environment.ProcessPath}\" {BackgroundArgument}");
            else key.DeleteValue(Name, throwOnMissingValue: false);
        }
    }

    /// Points an existing entry at this copy of the app.
    public static void Refresh()
    {
        if (IsEnabled) IsEnabled = true;
    }
}
