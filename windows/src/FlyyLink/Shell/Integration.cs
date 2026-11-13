using Microsoft.Win32;

namespace FlyyLink.Shell;

/// Hooks FlyyLink into Explorer and Windows for the current user: "Send to phone" on files, and calling tel: links.
internal static class Integration
{
    private const string Classes = @"Software\Classes";
    private const string SendVerb = @"Software\Classes\*\shell\FlyyLink.Send";
    private const string TelProgId = "FlyyLink.tel";
    private const string Capabilities = @"Software\FlyyLink\Capabilities";

    /// Passed with each file picked from "Send to phone".
    public const string SendArgument = "--send";

    /// Writes the entries again on every launch, so they follow the app when its folder moves.
    public static void Register()
    {
        var exe = Environment.ProcessPath;
        if (exe is null) return;

        try
        {
            using (var verb = Registry.CurrentUser.CreateSubKey(SendVerb))
            {
                verb.SetValue("", "Send to phone");
                verb.SetValue("Icon", $"\"{exe}\",0");
                using var command = verb.CreateSubKey("command");
                command.SetValue("", $"\"{exe}\" {SendArgument} \"%1\"");
            }

            using (var tel = Registry.CurrentUser.CreateSubKey($@"{Classes}\{TelProgId}"))
            {
                tel.SetValue("", "Call with your phone");
                tel.SetValue("FriendlyTypeName", "Call with your phone");
                using (var icon = tel.CreateSubKey("DefaultIcon")) icon.SetValue("", $"\"{exe}\",0");
                using var command = tel.CreateSubKey(@"shell\open\command");
                command.SetValue("", $"\"{exe}\" \"%1\"");
            }

            // Listed in Settings > Default apps, where the user can make FlyyLink the app for tel: links.
            using (var capabilities = Registry.CurrentUser.CreateSubKey(Capabilities))
            {
                capabilities.SetValue("ApplicationName", "FlyyLink");
                capabilities.SetValue("ApplicationDescription", "Calls and texts from your Android phone");
                using var urls = capabilities.CreateSubKey("URLAssociations");
                urls.SetValue("tel", TelProgId);
            }

            using var registered = Registry.CurrentUser.CreateSubKey(@"Software\RegisteredApplications");
            registered.SetValue("FlyyLink", Capabilities);
        }
        catch (Exception e) when (e is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            System.Diagnostics.Debug.WriteLine($"Shell integration failed: {e.Message}");
        }
    }
}
