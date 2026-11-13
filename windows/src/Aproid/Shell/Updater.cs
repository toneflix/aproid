using System.Diagnostics;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json.Serialization;
using Aproid.Plugins;
using Microsoft.Windows.AppNotifications.Builder;

namespace Aproid.Shell;

/// Looks for a newer Windows release on the website and installs it when the user agrees.
internal sealed class Updater(ToastCenter toasts)
{
    private const string Feed = "https://aproid.toneflix.com/updates/windows.json";
    private static readonly TimeSpan FirstCheck = TimeSpan.FromMinutes(2);
    private static readonly TimeSpan CheckEvery = TimeSpan.FromHours(12);

    /// The running app's version.
    public static Version Current { get; } = Trim(Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(0, 0, 0));

    private static readonly HttpClient Http = CreateClient();

    private Version? offered;

    /// Called on a background thread once the installer is running, so the app can quit and let it replace the files.
    public Action? OnInstalling { get; set; }

    /// The version shown to the user, like 1.2.3.
    public static string CurrentText => Current.ToString(3);

    /// Checks shortly after launch, then twice a day, offering each new version once.
    public void Start() => _ = Task.Run(async () =>
    {
        await Task.Delay(FirstCheck);
        while (true)
        {
            await CheckAsync(manual: false);
            await Task.Delay(CheckEvery);
        }
    });

    /// `manual` also says when FlyyLink is up to date or the check failed.
    public async Task CheckAsync(bool manual)
    {
        Release? newest;
        try
        {
            newest = await NewestAsync();
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            if (manual) Say("Couldn't check for updates", "Check your internet connection and try again.");
            return;
        }

        if (newest is null)
        {
            if (manual) Say("FlyyLink is up to date", $"You have version {CurrentText}.");
            return;
        }

        if (!manual && newest.Version == offered) return;

        offered = newest.Version;
        Offer(newest);
    }

    private sealed record Release(Version Version, string Installer, string Page);

    private static async Task<Release?> NewestAsync()
    {
        var feed = await Http.GetFromJsonAsync<FeedEntry>(Feed);
        if (feed is null || !Version.TryParse(feed.Version, out var version)) return null;

        version = Trim(version);

        return version > Current ? new Release(version, feed.Installer, feed.Notes) : null;
    }

    private void Offer(Release release) => toasts.Show(
        key => new AppNotificationBuilder()
            .AddText($"FlyyLink {release.Version.ToString(3)} is available")
            .AddText($"You have {CurrentText}. FlyyLink restarts to update.")
            .AddButton(ToastCenter.Button("Update now", "update", key))
            .AddButton(ToastCenter.Button("What's new", "notes", key)),
        (action, input) =>
        {
            if (action == "update") _ = InstallAsync(release);
            else if (action == "notes") Explorer.Open(release.Page);
        },
        tag: "update",
        group: "aproid");

    private async Task InstallAsync(Release release)
    {
        var path = Path.Combine(Path.GetTempPath(), $"FlyyLink-Setup-{release.Version.ToString(3)}.exe");

        try
        {
            await using (var source = await Http.GetStreamAsync(release.Installer))
            await using (var file = File.Create(path))
            {
                await source.CopyToAsync(file);
            }

            // The installer closes FlyyLink, swaps the files and starts the new version.
            Process.Start(new ProcessStartInfo(path, "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART") { UseShellExecute = true });
            OnInstalling?.Invoke();
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            Say("Couldn't update FlyyLink", e.Message);
        }
    }

    private void Say(string title, string text) => toasts.Show(key => new AppNotificationBuilder().AddText(title).AddText(text), tag: "update", group: "aproid");

    private static Version Trim(Version version) => new(version.Major, version.Minor, Math.Max(version.Build, 0));

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"FlyyLink-Windows/{CurrentText}");

        return client;
    }

    private sealed class FeedEntry
    {
        [JsonPropertyName("version")] public string Version { get; set; } = "";
        [JsonPropertyName("installer")] public string Installer { get; set; } = "";
        [JsonPropertyName("notes")] public string Notes { get; set; } = "";
    }
}
