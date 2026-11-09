using Aproid.Core;

namespace Aproid.Plugins;

/// Receives the phone's screen stream ("aproid.screen") and hands on each frame.
internal sealed class ScreenPlugin : IPlugin
{
    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.Screen };

    /// Called on a network thread when a phone starts streaming, with the picture's size.
    public Action<Device, Screen.Info>? OnStarted { get; set; }

    /// Called on a network thread with each frame, in order.
    public Action<ScreenFrame>? OnFrame { get; set; }

    /// Called on a network thread with the phone's id when its stream ends.
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
        _ = ReadAsync(packet, device);
    }

    private async Task ReadAsync(NetworkPacket packet, Device device)
    {
        var reader = new ScreenFrameReader();

        try
        {
            await device.ReceiveStreamAsync(packet, data =>
            {
                foreach (var frame in reader.Feed(data.Span)) OnFrame?.Invoke(frame);

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
