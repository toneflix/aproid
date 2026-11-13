using System.Text.Json.Nodes;

namespace Aproid.Core;

/// A phone's packets passed on by one computer to another that isn't connected to that phone ("flyylink.relay").
/// The computer next to the phone wraps what the phone sends, such as notifications and calls. The other computer
/// wraps its answers, such as replies and call buttons, and the first one hands them to the phone. Payloads are not
/// relayed. Mirrors Relay.kt and Relay.swift.
public static class Relay
{
    /// What a computer passes on from a phone.
    public static readonly IReadOnlySet<string> FromPhone = new HashSet<string> { PacketType.Notification, PacketType.Telephony };

    /// What a computer passes on to a phone.
    public static readonly IReadOnlySet<string> ToPhone = new HashSet<string>
    {
        PacketType.NotificationRequest,
        PacketType.NotificationReply,
        PacketType.NotificationAction,
        PacketType.CallRequest,
    };

    public sealed record Message(string PhoneId, string PhoneName, NetworkPacket Packet);

    public static NetworkPacket Wrap(NetworkPacket packet, string phoneId, string phoneName) => new(PacketType.Relay, new JsonObject
    {
        ["phoneId"] = phoneId,
        ["phoneName"] = phoneName,
        ["packet"] = new JsonObject { ["type"] = packet.Type, ["body"] = packet.Body.DeepClone() },
    });

    /// The wrapped packet, or null when it isn't one that may be relayed.
    public static Message? MessageOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Relay || packet.GetString("phoneId") is not { Length: > 0 } phoneId) return null;
        if (packet.Body["packet"] is not JsonObject inner || inner["type"].AsString() is not string type) return null;
        if (!FromPhone.Contains(type) && !ToPhone.Contains(type)) return null;

        var body = inner["body"] is JsonObject wrapped ? (JsonObject)wrapped.DeepClone() : [];
        var name = packet.GetString("phoneName") is { Length: > 0 } given ? given : "Phone";

        return new Message(phoneId, name, new NetworkPacket(type, body, packet.Id));
    }
}
