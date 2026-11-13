using FlyyLink.Core;

namespace FlyyLink.Model;

/// The connected devices, by id. Safe to use from any thread.
internal sealed class DeviceRegistry
{
    private readonly Dictionary<string, Device> devices = [];
    private readonly object gate = new();

    public Device? this[string id]
    {
        get
        {
            lock (gate) return devices.GetValueOrDefault(id);
        }
    }

    public IReadOnlyList<Device> All
    {
        get
        {
            lock (gate) return [.. devices.Values];
        }
    }

    public IReadOnlyList<Device> Paired => All.Where(d => d.IsPaired).ToList();

    public IReadOnlyList<Device> PairedPhones => Paired.Where(d => !d.Link.Identity.DeviceType.IsComputer()).ToList();

    /// Adds or replaces the device and returns the one it replaced.
    public Device? Insert(Device device)
    {
        lock (gate)
        {
            var old = devices.GetValueOrDefault(device.Id);
            devices[device.Id] = device;

            return old;
        }
    }

    /// Removes the device unless a newer link already took its place.
    public bool Remove(Device device)
    {
        lock (gate)
        {
            if (devices.GetValueOrDefault(device.Id) != device) return false;

            return devices.Remove(device.Id);
        }
    }
}
