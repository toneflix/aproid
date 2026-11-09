using Aproid.Core;

namespace Aproid.Plugins;

/// Follows the phone's calls ("kdeconnect.telephony").
internal sealed class CallPlugin : IPlugin
{
    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.Telephony };

    /// Called on a network thread with each call update.
    public Action<Call.State, Device>? OnState { get; set; }

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (Call.StateOf(packet) is Call.State state) OnState?.Invoke(state, device);
    }
}
