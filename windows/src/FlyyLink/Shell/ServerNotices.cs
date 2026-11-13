using FlyyLink.Model;
using FlyyLink.Plugins;
using Microsoft.Windows.AppNotifications.Builder;

namespace FlyyLink.Shell;

/// Notices the FlyyLink team sends with `flyylink-cli notify:send --channel=app`, shown as Windows notifications.
/// Fetched when the licence is checked; the first fetch only records where to start. Mirrors ServerNotices.swift.
internal sealed class ServerNotices(LicenceServer server, ToastCenter toasts)
{
    public async Task CheckAsync(string machine, string? secret)
    {
        try
        {
            var reply = await server.NoticesAsync(machine, secret, Last());

            foreach (var notice in reply.Items) Show(notice);
            File.WriteAllText(AppPaths.ServerNotices, reply.Latest.ToString());
        }
        catch (Exception e) when (e is LicenceServerException or HttpRequestException or TaskCanceledException or System.Text.Json.JsonException or IOException)
        {
        }
    }

    private static int? Last()
    {
        try
        {
            return int.TryParse(File.ReadAllText(AppPaths.ServerNotices), out var last) ? last : null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    private void Show(LicenceServer.Notice notice) => toasts.Show(
        key =>
        {
            var builder = new AppNotificationBuilder().AddText(notice.Title).AddText(notice.Message);

            return notice.Link is null ? builder : builder.AddButton(ToastCenter.Button(notice.LinkText ?? "Open", "link", key));
        },
        (action, _) =>
        {
            if (notice.Link is string link && link.StartsWith("https://", StringComparison.Ordinal)) Explorer.Open(link);
        },
        tag: $"notice-{notice.Id}",
        group: "flyylink");
}
