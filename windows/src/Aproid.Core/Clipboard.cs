using System.Text.Json.Nodes;

namespace Aproid.Core;

/// A copied picture or file. `SafeName` has no folders, so it can't be saved outside the target folder.
public sealed record ClipboardFile(string Name, string MimeType)
{
    public string SafeName => Share.SafeName(Name);
}

/// Shared clipboard text ("kdeconnect.clipboard" and "kdeconnect.clipboard.connect"), and copied files
/// ("flyylink.clipboard.file"). Mirrors Clipboard.kt and Clipboard.swift.
public static class Clipboard
{
    /// Bigger copies are left alone, so copying a film doesn't start a long transfer.
    public const long FileLimit = 50 * 1024 * 1024;

    /// Announces a copied file. Send it with `Device.SendWithPayload`.
    public static NetworkPacket FilePacket(string name, string mimeType) =>
        new(PacketType.ClipboardFile, new JsonObject { ["name"] = name, ["mimeType"] = mimeType });

    public static ClipboardFile? File(NetworkPacket packet)
    {
        if (packet.Type != PacketType.ClipboardFile || packet.PayloadSize is null || packet.GetString("name") is not string name) return null;

        return new ClipboardFile(name, packet.GetString("mimeType") ?? "application/octet-stream");
    }

    public static NetworkPacket Packet(string content) => new(PacketType.Clipboard, new JsonObject { ["content"] = content });

    /// Sent right after connecting, so the peer can tell whether it is newer than its own.
    public static NetworkPacket ConnectPacket(string content, long timestampMillis) =>
        new(PacketType.ClipboardConnect, new JsonObject { ["content"] = content, ["timestamp"] = timestampMillis });

    /// The text in either clipboard packet, or null.
    public static string? Content(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Clipboard && packet.Type != PacketType.ClipboardConnect) return null;

        return packet.GetString("content") is { Length: > 0 } content ? content : null;
    }
}
