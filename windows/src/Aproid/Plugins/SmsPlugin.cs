using Aproid.Core;

namespace Aproid.Plugins;

/// Hands text messages from the phone to the Messages window ("kdeconnect.sms.messages").
internal sealed class SmsPlugin : IPlugin
{
    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.SmsMessages };

    /// Called on a network thread with the messages and the phone they came from.
    public Action<IReadOnlyList<SmsMessage>, string>? OnMessages { get; set; }

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (Sms.Messages(packet) is { } messages) OnMessages?.Invoke(messages, device.Id);
    }
}
