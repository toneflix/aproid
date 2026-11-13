using System.Text.Json.Nodes;

namespace FlyyLink.Core;

/// One photo or video in the phone's gallery. `Date` is when it was taken, in milliseconds; `Thumbnail` is base64 JPEG.
/// Mirrors PhonePhoto in Photos.kt and Photos.swift.
public sealed record PhonePhoto(
    long Id,
    string Name,
    long Date,
    string MimeType,
    long Width = 0,
    long Height = 0,
    long Size = 0,
    string? Thumbnail = null)
{
    public bool IsVideo => MimeType.StartsWith("video/", StringComparison.Ordinal);

    public static PhonePhoto? FromJson(JsonObject json)
    {
        if (json["id"].AsLong() is not long id) return null;

        return new PhonePhoto(
            id,
            json["name"].AsString() ?? "",
            json["date"].AsLong() ?? 0,
            json["mimeType"].AsString() ?? "image/jpeg",
            json["width"].AsLong() ?? 0,
            json["height"].AsLong() ?? 0,
            json["size"].AsLong() ?? 0,
            json["thumbnail"].AsString());
    }

    public JsonObject ToJson()
    {
        var json = new JsonObject
        {
            ["id"] = Id,
            ["name"] = Name,
            ["date"] = Date,
            ["mimeType"] = MimeType,
            ["width"] = Width,
            ["height"] = Height,
            ["size"] = Size,
        };
        if (Thumbnail is not null) json["thumbnail"] = Thumbnail;

        return json;
    }
}

/// Browsing the phone's gallery. Full photos come back as normal shared files, or as "flyylink.photos.file" to view.
/// Mirrors Photos.kt and Photos.swift.
public static class Photos
{
    public const int PageSize = 40;

    public sealed record Request(long? Before, long Count);

    public sealed record Page(IReadOnlyList<PhonePhoto> Items, bool More);

    /// A request for one photo in full; `Preview` asks for it to view instead of to keep.
    public sealed record Download(long Id, bool Preview);

    /// A full photo or video sent to view.
    public sealed record File(long Id, string Name, string MimeType);

    public static NetworkPacket RequestPacket(long? before = null, long count = PageSize)
    {
        var body = new JsonObject { ["count"] = count };
        if (before is long value) body["before"] = value;

        return new NetworkPacket(PacketType.PhotosRequest, body);
    }

    public static Request? RequestOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.PhotosRequest) return null;

        var before = packet.GetLong("before") is long value and > 0 ? value : (long?)null;

        return new Request(before, Math.Clamp(packet.GetLong("count") ?? PageSize, 1, 200));
    }

    public static NetworkPacket PagePacket(IEnumerable<PhonePhoto> photos, bool more) => new(PacketType.Photos, new JsonObject
    {
        ["photos"] = new JsonArray(photos.Select(photo => (JsonNode?)photo.ToJson()).ToArray()),
        ["more"] = more,
    });

    public static Page? PageOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Photos) return null;

        var photos = (packet.Body["photos"] as JsonArray ?? [])
            .OfType<JsonObject>()
            .Select(PhonePhoto.FromJson)
            .OfType<PhonePhoto>()
            .ToList();

        return new Page(photos, packet.GetBool("more") ?? false);
    }

    public static NetworkPacket DownloadPacket(long id, bool preview = false)
    {
        var body = new JsonObject { ["id"] = id };
        if (preview) body["preview"] = true;

        return new NetworkPacket(PacketType.PhotosDownload, body);
    }

    public static Download? DownloadOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.PhotosDownload || packet.GetLong("id") is not long id) return null;

        return new Download(id, packet.GetBool("preview") ?? false);
    }

    public static NetworkPacket FilePacket(File file) => new(PacketType.PhotosFile, new JsonObject
    {
        ["id"] = file.Id,
        ["name"] = file.Name,
        ["mimeType"] = file.MimeType,
    });

    public static File? FileOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.PhotosFile || packet.GetLong("id") is not long id) return null;

        return new File(id, packet.GetString("name") ?? "", packet.GetString("mimeType") ?? "image/jpeg");
    }
}
