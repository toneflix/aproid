using FlyyLink.Core;
using FlyyLink.Model;

namespace FlyyLink.Plugins;

/// Passes a phone's notifications and calls on to paired computers that aren't connected to it, and their
/// replies and call buttons back to the phone ("flyylink.relay").
internal sealed class PhoneRelayPlugin(DeviceRegistry devices, Settings settings) : IPlugin
{
    private readonly object gate = new();

    /// Which computer each relayed phone is reached through.
    private readonly Dictionary<string, string> routes = [];

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string>(Relay.FromPhone) { PacketType.Relay };

    /// Called on a network thread with a phone's packet that another computer passed on, and that computer's name.
    public Action<Relay.Message, string>? OnRelayed { get; set; }

    /// Whether phones are passed on to and from other computers.
    public bool IsEnabled
    {
        get => settings.RelaysPhones;
        set => settings.RelaysPhones = value;
    }

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (!IsEnabled) return;

        if (device.Link.Identity.DeviceType.IsComputer())
        {
            if (Relay.MessageOf(packet) is Relay.Message message) Received(message, device);
            return;
        }

        if (!Relay.FromPhone.Contains(packet.Type)) return;

        foreach (var computer in devices.Paired.Where(d => d.Link.Identity.DeviceType.IsComputer()))
        {
            computer.Send(Relay.Wrap(packet, device.Id, device.Name));
        }
    }

    /// Sends a packet to a phone this PC only reaches through another computer. False when there is no route.
    public bool Send(NetworkPacket packet, string phoneId)
    {
        if (!IsEnabled || !Relay.ToPhone.Contains(packet.Type)) return false;

        string? via;
        lock (gate) routes.TryGetValue(phoneId, out via);

        return via is not null && devices[via] is { IsPaired: true } computer && computer.Send(Relay.Wrap(packet, phoneId, ""));
    }

    /// A computer disconnected: phones reached through it are gone too.
    public void Forget(string deviceId)
    {
        lock (gate)
        {
            foreach (var phone in routes.Where(route => route.Value == deviceId).Select(route => route.Key).ToList()) routes.Remove(phone);
        }
    }

    private void Received(Relay.Message message, Device computer)
    {
        if (Relay.ToPhone.Contains(message.Packet.Type))
        {
            if (devices[message.PhoneId] is { IsPaired: true } phone && !phone.Link.Identity.DeviceType.IsComputer()) phone.Send(message.Packet);
            return;
        }

        // Connected to the phone directly, so this already arrived first hand.
        if (devices[message.PhoneId] is { IsPaired: true }) return;

        lock (gate) routes[message.PhoneId] = computer.Id;
        OnRelayed?.Invoke(message, computer.Name);
    }
}
