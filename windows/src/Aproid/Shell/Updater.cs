using System.Diagnostics;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json.Serialization;
using Aproid.Plugins;
using Microsoft.Windows.AppNotifications.Builder;

namespace Aproid.Shell;

/// Looks for a newer Windows release on GitHub and installs it when the user agrees.
/// Releases are tagged 1.2.3 (all apps) or windows-1.2.3 and carry Aproid-Setup-1.2.3.exe.
internal sealed class Updater(ToastCenter toasts)
{
    private const string Releases = "https://api.github.com/repos/toneflix/aproid/releases?per_page=30";
    private static readonly string[] TagPrefixes = ["windows-v", "windows-", "v", ""];
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

    /// `manual` also says when Aproid is up to date or the check failed.
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
            if (manual) Say("Aproid is up to date", $"You have version {CurrentText}.");
            return;
        }

        if (!manual && newest.Version == offered) return;

        offered = newest.Version;
        Offer(newest);
    }

    private sealed record Release(Version Version, string Installer, string Page);

    private static async Task<Release?> NewestAsync()
    {
        var releases = await Http.GetFromJsonAsync<List<GitHubRelease>>(Releases) ?? [];

        return releases
            .Where(r => !r.Draft && !r.Prerelease)
            .Select(r => (Release: r, Version: ParseTag(r.Tag)))
            .Where(r => r.Version is not null && r.Version > Current)
            .Select(r => (r.Version, Asset: r.Release.Assets.FirstOrDefault(a => a.Name.StartsWith("Aproid-Setup", StringComparison.Ordinal) && a.Name.EndsWith(".exe", StringComparison.Ordinal)), r.Release.Page))
            .Where(r => r.Asset is not null)
            .OrderByDescending(r => r.Version)
            .Select(r => new Release(r.Version!, r.Asset!.Url, r.Page))
            .FirstOrDefault();
    }

    private void Offer(Release release) => toasts.Show(
        key => new AppNotificationBuilder()
            .AddText($"Aproid {release.Version.ToString(3)} is available")
            .AddText($"You have {CurrentText}. Aproid restarts to update.")
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
        var path = Path.Combine(Path.GetTempPath(), $"Aproid-Setup-{release.Version.ToString(3)}.exe");

        try
        {
            await using (var source = await Http.GetStreamAsync(release.Installer))
            await using (var file = File.Create(path))
            {
                await source.CopyToAsync(file);
            }

            // The installer closes Aproid, swaps the files and starts the new version.
            Process.Start(new ProcessStartInfo(path, "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART") { UseShellExecute = true });
            OnInstalling?.Invoke();
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            Say("Couldn't update Aproid", e.Message);
        }
    }

    private void Say(string title, string text) => toasts.Show(key => new AppNotificationBuilder().AddText(title).AddText(text), tag: "update", group: "aproid");

    private static Version? ParseTag(string tag)
    {
        var prefix = TagPrefixes.FirstOrDefault(p => tag.StartsWith(p, StringComparison.Ordinal));

        return prefix is not null && Version.TryParse(tag[prefix.Length..], out var version) ? Trim(version) : null;
    }

    private static Version Trim(Version version) => new(version.Major, version.Minor, Math.Max(version.Build, 0));

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"Aproid-Windows/{CurrentText}");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");

        return client;
    }

    private sealed class GitHubRelease
    {
        [JsonPropertyName("tag_name")] public string Tag { get; set; } = "";
        [JsonPropertyName("html_url")] public string Page { get; set; } = "";
        [JsonPropertyName("draft")] public bool Draft { get; set; }
        [JsonPropertyName("prerelease")] public bool Prerelease { get; set; }
        [JsonPropertyName("assets")] public List<GitHubAsset> Assets { get; set; } = [];
    }

    private sealed class GitHubAsset
    {
        [JsonPropertyName("name")] public string Name { get; set; } = "";
        [JsonPropertyName("browser_download_url")] public string Url { get; set; } = "";
    }
}
