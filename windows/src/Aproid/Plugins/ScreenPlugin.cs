using Aproid.Core;

namespace Aproid.Plugins;

/// Receives screen streams ("flyylink.screen"). A phone's H.264 frames go to `OnFrame`; another computer's JPEG
/// pictures go to `OnPicture`.
internal sealed class ScreenPlugin : IPlugin
{
    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.Screen };

    /// Called on a network thread when a device starts streaming, with the picture's size.
    public Action<Device, Screen.Info>? OnStarted { get; set; }

    /// Called on a network thread with each frame, in order.
    public Action<ScreenFrame>? OnFrame { get; set; }

    /// Called on a network thread with each JPEG picture from a computer, in order.
    public Action<byte[]>? OnPicture { get; set; }

    /// Called on a network thread with the device's id when its stream ends.
    public Action<string>? OnEnded { get; set; }

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (Screen.InfoOf(packet) is not Screen.Info info) return;

        var deviceId = device.Id;
        if (!info.Running || packet.PayloadSize != Screen.Stream)
        {
            OnEnded?.Invoke(deviceId);
            return;
        }

        OnStarted?.Invoke(device, info);
        Action<ScreenFrame> handle = info.Codec == Screen.Jpeg
            ? frame =>
            {
                if (!frame.IsAudio) OnPicture?.Invoke(frame.Data);
            }
            : frame => OnFrame?.Invoke(frame);
        _ = ReadAsync(packet, device, handle);
    }

    private async Task ReadAsync(NetworkPacket packet, Device device, Action<ScreenFrame> handle)
    {
        var reader = new ScreenFrameReader();

        try
        {
            await device.ReceiveStreamAsync(packet, data =>
            {
                foreach (var frame in reader.Feed(data.Span)) handle(frame);

                return ValueTask.CompletedTask;
            });
        }
        catch (Exception e) when (e is not OutOfMemoryException)
        {
            System.Diagnostics.Debug.WriteLine($"Screen stream ended: {e.Message}");
        }

        OnEnded?.Invoke(device.Id);
    }
}
