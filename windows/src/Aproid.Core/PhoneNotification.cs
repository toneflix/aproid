using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace Aproid.Core;

/// A notification mirrored from the phone ("kdeconnect.notification").
/// `ReplyId` is set when the notification can be answered with text. `IconHash` names the icon sent as
/// the packet's payload, so the receiver can reuse one it already has. Mirrors PhoneNotification.kt and .swift.
public sealed record PhoneNotification(
    string Id,
    string AppName,
    string Title,
    string Text,
    long Time,
    bool IsClearable = true,
    string? ReplyId = null,
    bool Silent = false,
    string? IconHash = null)
{
    /// Null for removals and malformed packets.
    public static PhoneNotification? FromPacket(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Notification || packet.GetBool("isCancel") == true || packet.GetString("id") is not string id) return null;

        // KDE Connect sends the time as a string.
        var time = long.TryParse(packet.GetString("time"), out var parsed) ? parsed : packet.GetLong("time") ?? 0;
        var replyId = packet.GetString("requestReplyId");
        var iconHash = packet.GetString("payloadHash");

        return new PhoneNotification(
            id,
            packet.GetString("appName") ?? "",
            packet.GetString("title") ?? "",
            packet.GetString("text") ?? "",
            time,
            packet.GetBool("isClearable") ?? true,
            string.IsNullOrEmpty(replyId) ? null : replyId,
            packet.GetBool("silent") ?? false,
            string.IsNullOrEmpty(iconHash) ? null : iconHash);
    }

    public NetworkPacket ToPacket()
    {
        var body = new JsonObject
        {
            ["id"] = Id,
            ["appName"] = AppName,
            ["title"] = Title,
            ["text"] = Text,
            ["ticker"] = string.Join(": ", new[] { Title, Text }.Where(s => s.Length > 0)),
            ["time"] = Time.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["isClearable"] = IsClearable,
            ["silent"] = Silent,
        };
        if (ReplyId is not null) body["requestReplyId"] = ReplyId;
        if (IconHash is not null) body["payloadHash"] = IconHash;

        return new NetworkPacket(PacketType.Notification, body);
    }

    /// The hash KDE Connect uses to name notification icons: MD5, as lowercase hex.
    public static string HashIcon(byte[] icon) => Convert.ToHexString(MD5.HashData(icon)).ToLowerInvariant();

    public static NetworkPacket CancelPacket(string id) =>
        new(PacketType.Notification, new JsonObject { ["id"] = id, ["isCancel"] = true });

    /// The id of a removed notification, or null if the packet is not a removal.
    public static string? CancelledId(NetworkPacket packet) =>
        packet.Type == PacketType.Notification && packet.GetBool("isCancel") == true ? packet.GetString("id") : null;
}

/// Packets the computer sends back about notifications.
public static class NotificationRequests
{
    public static NetworkPacket RequestAll() => new(PacketType.NotificationRequest, new JsonObject { ["request"] = true });

    public static NetworkPacket Dismiss(string id) => new(PacketType.NotificationRequest, new JsonObject { ["cancel"] = id });

    public static NetworkPacket Reply(string replyId, string message) =>
        new(PacketType.NotificationReply, new JsonObject { ["requestReplyId"] = replyId, ["message"] = message });
}
