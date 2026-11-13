using Aproid.Core;

namespace Aproid.Plugins;

/// Remembers where each phone last said it was ("flyylink.location").
internal sealed class LocationPlugin : IPlugin
{
    private readonly Dictionary<string, PhoneLocation> locations = [];
    private readonly object gate = new();

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.Location };

    /// Called on a network thread when a phone reports a new location.
    public Action? OnChange { get; set; }

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (PhoneLocation.FromPacket(packet) is not PhoneLocation location) return;

        lock (gate)
        {
            // A fresh fix can arrive before the older last known one; keep the newest.
            if (locations.TryGetValue(device.Id, out var known) && known.Time > location.Time) return;

            locations[device.Id] = location;
        }

        OnChange?.Invoke();
    }

    public PhoneLocation? Location(string deviceId)
    {
        lock (gate) return locations.GetValueOrDefault(deviceId);
    }

    public void Request(Device device) => device.Send(PhoneLocation.Request());
}
