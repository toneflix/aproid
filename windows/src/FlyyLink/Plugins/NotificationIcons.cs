using FlyyLink.Core;
using FlyyLink.Model;

namespace FlyyLink.Plugins;

/// Phone notification icons, cached on disk by hash so each one crosses the network once.
internal sealed class NotificationIcons
{
    private static readonly TimeSpan DownloadTimeout = TimeSpan.FromSeconds(8);

    private readonly string folder = Directory.CreateDirectory(Path.Combine(AppPaths.Cache, "NotificationIcons")).FullName;

    /// The icon file for `packet`, downloading it first if needed, or null when there is none.
    public async Task<string?> IconAsync(NetworkPacket packet, string? hash, Device device)
    {
        // The hash becomes a file name, so allow only what an MD5 hash looks like.
        if (hash is not { Length: 32 } || !hash.All(Uri.IsHexDigit)) return null;

        var cached = Path.Combine(folder, $"{hash}.png");
        if (File.Exists(cached)) return cached;
        if (packet.PayloadSize is null) return null;

        var partial = Path.Combine(folder, $"{hash}.{Guid.NewGuid():N}.part");
        try
        {
            using var timeout = new CancellationTokenSource(DownloadTimeout);
            await using (var sink = File.Create(partial))
            {
                await device.ReceivePayloadAsync(packet, sink, cancellation: timeout.Token);
            }

            // Another notification may have brought the same icon meanwhile.
            if (!File.Exists(cached)) File.Move(partial, cached);
        }
        catch (Exception e) when (e is not OutOfMemoryException)
        {
            System.Diagnostics.Debug.WriteLine($"Icon download failed: {e.Message}");
        }
        finally
        {
            File.Delete(partial);
        }

        return File.Exists(cached) ? cached : null;
    }
}
