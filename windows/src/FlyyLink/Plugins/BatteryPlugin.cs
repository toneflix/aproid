using FlyyLink.Core;
using FlyyLink.Model;
using FlyyLink.Shell;
using Microsoft.Windows.AppNotifications.Builder;

namespace FlyyLink.Plugins;

/// Keeps each device's battery level for the panel and alerts when one runs low. Tells paired devices this PC's own level.
internal sealed class BatteryPlugin : IPlugin
{
    private readonly Dictionary<string, BatteryStatus> levels = [];
    private readonly object gate = new();
    private readonly ToastCenter toasts;
    private readonly DeviceRegistry devices;
    private readonly SystemBattery own = new();
    private BatteryStatus? lastSent;

    public BatteryPlugin(ToastCenter toasts, DeviceRegistry devices)
    {
        this.toasts = toasts;
        this.devices = devices;

        own.OnChange = OwnChanged;
        own.Start();
    }

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.Battery, PacketType.BatteryRequest };

    /// Called on a background thread when a level changes.
    public Action? OnChange { get; set; }

    public BatteryStatus? Status(string deviceId)
    {
        lock (gate) return levels.GetValueOrDefault(deviceId);
    }

    public void OnPaired(Device device) => device.Send(BatteryStatus.Request());

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (packet.Type == PacketType.BatteryRequest)
        {
            if (SystemBattery.Current() is BatteryStatus mine) device.Send(mine.ToPacket());
            return;
        }

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

    /// Sends this PC's level to every paired device when it moves.
    private void OwnChanged()
    {
        if (SystemBattery.Current() is not BatteryStatus status) return;

        lock (gate)
        {
            if (status == lastSent) return;

            lastSent = status;
        }

        foreach (var device in devices.Paired) device.Send(status.ToPacket());
    }
}
