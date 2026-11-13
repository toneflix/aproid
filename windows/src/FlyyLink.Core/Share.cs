using System.Text.Json.Nodes;

namespace FlyyLink.Core;

/// What a "kdeconnect.share.request" carries: a file, a link or some text. Mirrors Share.kt and Share.swift.
public abstract record Share
{
    /// `TransferId` lets an interrupted file be resumed; `Offset` is where this payload starts in the file,
    /// so `Size` is only what is left. Both are our own fields, which KDE Connect ignores.
    public sealed record File(string Name, long Size, string? TransferId = null, long Offset = 0) : Share;

    public sealed record Link(string Url) : Share;

    public sealed record Text(string Content) : Share;

    /// The packet announcing a file. Send it with `Device.SendWithPayload`, which adds the payload.
    public static NetworkPacket FilePacket(string name, long size, long? lastModifiedMillis = null, string? transferId = null, long offset = 0)
    {
        var body = new JsonObject
        {
            ["filename"] = name,
            ["numberOfFiles"] = 1,
            ["totalPayloadSize"] = size,
        };
        if (lastModifiedMillis is long modified) body["lastModified"] = modified;
        if (transferId is not null) body["flyylink.transferId"] = transferId;
        if (offset > 0) body["flyylink.offset"] = offset;

        return new NetworkPacket(PacketType.ShareRequest, body);
    }

    /// Asks the sender for the rest of `transferId`, from byte `offset`.
    public static NetworkPacket ResumePacket(string transferId, long offset) =>
        new(PacketType.ShareResume, new JsonObject { ["transferId"] = transferId, ["offset"] = offset });

    /// The transfer and offset a resume packet asks for.
    public static (string TransferId, long Offset)? ResumeRequest(NetworkPacket packet)
    {
        if (packet.Type != PacketType.ShareResume || packet.GetString("transferId") is not string id || packet.GetLong("offset") is not (long offset and >= 0))
            return null;

        return (id, offset);
    }

    public static NetworkPacket LinkPacket(string url) => new(PacketType.ShareRequest, new JsonObject { ["url"] = url });

    public static NetworkPacket TextPacket(string text) => new(PacketType.ShareRequest, new JsonObject { ["text"] = text });

    public static Share? FromPacket(NetworkPacket packet)
    {
        if (packet.Type != PacketType.ShareRequest) return null;

        if (packet.GetString("filename") is string name)
        {
            if (packet.PayloadSize is not long size) return null;

            return new File(name, size, packet.GetString("flyylink.transferId"), Math.Max(packet.GetLong("flyylink.offset") ?? 0, 0));
        }

        if (packet.GetString("url") is string url) return new Link(url);
        if (packet.GetString("text") is string text) return new Text(text);

        return null;
    }

    /// A file name without any folders, so a peer can't write outside the download folder.
    public static string SafeName(string name)
    {
        var last = name.Split('/', '\\').LastOrDefault(part => part.Length > 0) ?? "";
        var trimmed = last.TrimStart('.');
        var cleaned = new string(trimmed.Where(c => !Path.GetInvalidFileNameChars().Contains(c) && !"<>:\"|?*".Contains(c)).ToArray());

        return cleaned.Length == 0 ? "file" : cleaned;
    }
}
