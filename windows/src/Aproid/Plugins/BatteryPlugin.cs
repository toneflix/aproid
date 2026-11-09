using Aproid.Core;
using Microsoft.Windows.AppNotifications.Builder;

namespace Aproid.Plugins;

/// Keeps each phone's battery level for the panel, and alerts when a phone runs low.
internal sealed class BatteryPlugin(ToastCenter toasts) : IPlugin
{
    private readonly Dictionary<string, BatteryStatus> levels = [];
    private readonly object gate = new();

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.Battery };

    /// Called on a background thread when a level changes.
    public Action? OnChange { get; set; }

    public BatteryStatus? Status(string deviceId)
    {
        lock (gate) return levels.GetValueOrDefault(deviceId);
    }

    public void OnPaired(Device device) => device.Send(BatteryStatus.Request());

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (BatteryStatus.FromPacket(packet) is not BatteryStatus status) return;

        bool wasLow;
        lock (gate)
        {
            wasLow = levels.GetValueOrDefault(device.Id)?.IsLow ?? false;
            levels[device.Id] = status;
        }

        if (status.IsLow && !wasLow)
        {
            toasts.Show(_ => new AppNotificationBuilder()
                .AddText($"{device.Name} battery is low")
                .AddText($"{status.Charge}% left. Plug it in soon."), tag: "battery", group: device.Id);
        }

        OnChange?.Invoke();
    }
}
