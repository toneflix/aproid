using Aproid.Core;
using Aproid.Model;

namespace Aproid.Plugins;

/// Receives pages of the phone's gallery ("flyylink.photos") and full photos to view ("flyylink.photos.file").
internal sealed class PhotosPlugin : IPlugin
{
    /// Viewed photos are only kept until the next launch.
    private readonly string cache = Path.Combine(AppPaths.Cache, "Photos");

    public PhotosPlugin()
    {
        try
        {
            if (Directory.Exists(cache)) Directory.Delete(cache, recursive: true);
        }
        catch (IOException)
        {
        }
    }

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.Photos, PacketType.PhotosFile };

    /// Called on a network thread with each page and the phone it came from.
    public Action<Photos.Page, string>? OnPage { get; set; }

    /// Called once a photo to view has arrived, with its id, where it was saved (null when it failed) and the phone.
    public Action<long, string?, string>? OnPreview { get; set; }

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (Photos.PageOf(packet) is Photos.Page page) OnPage?.Invoke(page, device.Id);
        else if (Photos.FileOf(packet) is Photos.File file) _ = ReceiveAsync(file, packet, device);
    }

    private async Task ReceiveAsync(Photos.File file, NetworkPacket packet, Device device)
    {
        var folder = Directory.CreateDirectory(Path.Combine(cache, file.Id.ToString())).FullName;
        var target = Path.Combine(folder, Share.SafeName(file.Name));

        try
        {
            await using (var sink = File.Create(target))
            {
                await device.ReceivePayloadAsync(packet, sink);
            }

            OnPreview?.Invoke(file.Id, target, device.Id);
        }
        catch (Exception e) when (e is not OutOfMemoryException)
        {
            File.Delete(target);
            OnPreview?.Invoke(file.Id, null, device.Id);
        }
    }
}
