using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Aproid.Core;

/// One KDE Connect packet. On the wire it is a single line of JSON ending in "\n".
/// Mirrors NetworkPacket.kt and NetworkPacket.swift.
public sealed class NetworkPacket
{
    private static readonly JsonWriterOptions WriterOptions = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    public long Id { get; set; }

    public string Type { get; set; }

    public JsonObject Body { get; set; }

    public long? PayloadSize { get; set; }

    public JsonObject? PayloadTransferInfo { get; set; }

    public NetworkPacket(string type, JsonObject? body = null, long? id = null, long? payloadSize = null, JsonObject? payloadTransferInfo = null)
    {
        Type = type;
        Body = body ?? [];
        Id = id ?? DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        PayloadSize = payloadSize;
        PayloadTransferInfo = payloadTransferInfo;
    }

    public string? GetString(string key) => Body[key].AsString();

    public long? GetLong(string key) => Body[key].AsLong();

    public bool? GetBool(string key) => Body[key].AsBool();

    public double? GetDouble(string key) => Body[key].AsDouble();

    public IReadOnlyList<string> GetStringList(string key) => Body[key].AsStringList();

    /// The port the sender opened for this packet's payload.
    public int? PayloadPort => PayloadTransferInfo?["port"].AsLong() is long port and > 0 and <= ushort.MaxValue ? (int)port : null;

    public byte[] Serialize()
    {
        var root = new JsonObject
        {
            ["id"] = Id,
            ["type"] = Type,
            ["body"] = Body.DeepClone(),
        };
        if (PayloadSize is long size) root["payloadSize"] = size;
        if (PayloadTransferInfo is not null) root["payloadTransferInfo"] = PayloadTransferInfo.DeepClone();

        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, WriterOptions))
        {
            JsonValues.WriteSorted(writer, root);
        }
        buffer.WriteByte((byte)'\n');

        return buffer.ToArray();
    }

    public static NetworkPacket Parse(ReadOnlySpan<byte> data)
    {
        JsonNode? root;
        try
        {
            root = JsonNode.Parse(data);
        }
        catch (JsonException)
        {
            throw new ProtocolException("invalid JSON");
        }

        if (root is not JsonObject obj) throw new ProtocolException("packet is not an object");
        if (obj["type"].AsString() is not string type) throw new ProtocolException("missing type");

        // Some older clients send the id as a string.
        var id = obj["id"].AsLong() ?? (long.TryParse(obj["id"].AsString(), out var parsed) ? parsed : 0);
        var body = Detach(obj, "body") ?? [];
        var info = Detach(obj, "payloadTransferInfo");

        return new NetworkPacket(type, body, id, obj["payloadSize"].AsLong(), info);
    }

    public static NetworkPacket Parse(string line) => Parse(Encoding.UTF8.GetBytes(line));

    public override string ToString() => Encoding.UTF8.GetString(Serialize()).TrimEnd('\n');

    private static JsonObject? Detach(JsonObject parent, string key)
    {
        if (parent[key] is not JsonObject child) return null;

        parent.Remove(key);

        return child;
    }
}
