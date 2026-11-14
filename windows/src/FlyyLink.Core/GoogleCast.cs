using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace FlyyLink.Core;

/// Where a Google Cast TV listens.
public sealed record CastEndpoint(string Host, int Port = GoogleCast.Port);

/// Google Cast: the messages that tell a Cast TV's built-in media player what to play. Mirrors GoogleCast.kt and GoogleCast.swift.
public static class GoogleCast
{
    public const int Port = 8009;
    public const string Service = "_googlecast._tcp.local";

    /// Google's Default Media Receiver, the player every Cast TV has.
    public const string MediaReceiver = "CC1AD845";

    public const string Sender = "sender-0";
    public const string Receiver = "receiver-0";

    public const string Connection = "urn:x-cast:com.google.cast.tp.connection";
    public const string Heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat";
    public const string ReceiverNamespace = "urn:x-cast:com.google.cast.receiver";
    public const string Media = "urn:x-cast:com.google.cast.media";

    /// Replies that mean a request failed.
    public static readonly IReadOnlySet<string> Failures = new HashSet<string> { "LAUNCH_ERROR", "LOAD_FAILED", "LOAD_CANCELLED", "INVALID_REQUEST", "INVALID_PLAYER_STATE" };

    public static JsonObject Connect() => new() { ["type"] = "CONNECT" };

    public static JsonObject Ping() => new() { ["type"] = "PING" };

    public static JsonObject Pong() => new() { ["type"] = "PONG" };

    public static JsonObject Launch(int requestId) => new() { ["type"] = "LAUNCH", ["requestId"] = requestId, ["appId"] = MediaReceiver };

    public static JsonObject ReceiverStatus(int requestId) => new() { ["type"] = "GET_STATUS", ["requestId"] = requestId };

    public static JsonObject StopApp(int requestId, string sessionId) => new() { ["type"] = "STOP", ["requestId"] = requestId, ["sessionId"] = sessionId };

    public static JsonObject SetVolume(int requestId, int volume) => new()
    {
        ["type"] = "SET_VOLUME",
        ["requestId"] = requestId,
        ["volume"] = new JsonObject { ["level"] = Math.Clamp(volume, 0, 100) / 100.0 },
    };

    public static JsonObject Load(int requestId, string url, string title, string mime) => new()
    {
        ["type"] = "LOAD",
        ["requestId"] = requestId,
        ["autoplay"] = true,
        ["media"] = new JsonObject
        {
            ["contentId"] = url,
            ["contentType"] = mime,
            ["streamType"] = "BUFFERED",
            ["metadata"] = new JsonObject { ["metadataType"] = MetadataType(mime), ["title"] = title },
        },
    };

    public static JsonObject MediaStatus(int requestId, long? mediaSessionId = null) => MediaCall("GET_STATUS", requestId, mediaSessionId);

    public static JsonObject Play(int requestId, long mediaSessionId) => MediaCall("PLAY", requestId, mediaSessionId);

    public static JsonObject Pause(int requestId, long mediaSessionId) => MediaCall("PAUSE", requestId, mediaSessionId);

    public static JsonObject Stop(int requestId, long mediaSessionId) => MediaCall("STOP", requestId, mediaSessionId);

    public static JsonObject Seek(int requestId, long mediaSessionId, long positionMs) => new()
    {
        ["type"] = "SEEK",
        ["requestId"] = requestId,
        ["mediaSessionId"] = mediaSessionId,
        ["currentTime"] = Math.Max(positionMs, 0) / 1000.0,
    };

    /// The JSON of a message, or null when it isn't a JSON object.
    public static JsonObject? Parse(string payload)
    {
        try
        {
            return JsonNode.Parse(payload) as JsonObject;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static string? Type(JsonObject message) => Text(message["type"]);

    public static int? RequestId(JsonObject message) => Number(message["requestId"]) is double id ? (int)id : null;

    /// The running Default Media Receiver in a RECEIVER_STATUS, or null while it isn't running.
    public static CastApp? MediaApp(JsonObject message)
    {
        if (Type(message) != "RECEIVER_STATUS" || (message["status"] as JsonObject)?["applications"] is not JsonArray apps) return null;

        var app = apps.OfType<JsonObject>().FirstOrDefault(a => Text(a["appId"]) == MediaReceiver);
        if (app is null || Text(app["sessionId"]) is not string session || Text(app["transportId"]) is not string transport) return null;

        return new CastApp(session, transport);
    }

    /// The TV's volume from 0 to 100 in a RECEIVER_STATUS.
    public static int? Volume(JsonObject message)
    {
        if (Type(message) != "RECEIVER_STATUS") return null;

        return Number(((message["status"] as JsonObject)?["volume"] as JsonObject)?["level"]) is double level
            ? (int)Math.Round(level * 100, MidpointRounding.AwayFromZero)
            : null;
    }

    /// What the player is doing in a MEDIA_STATUS. Null unless the message is one.
    public static CastMedia? MediaOf(JsonObject message)
    {
        if (Type(message) != "MEDIA_STATUS") return null;
        if ((message["status"] as JsonArray)?.FirstOrDefault() is not JsonObject status) return new CastMedia(null, CastState.Stopped, null);

        long? Milliseconds(JsonNode? value) => Number(value) is double seconds ? (long)(seconds * 1000) : null;

        var position = Milliseconds(status["currentTime"]);
        var duration = Milliseconds((status["media"] as JsonObject)?["duration"]);

        return new CastMedia(
            Number(status["mediaSessionId"]) is double id ? (long)id : null,
            State(Text(status["playerState"])),
            position is long at ? new CastPosition(at, Math.Max(duration ?? 0, 0)) : null);
    }

    public static CastState? State(string? playerState) => playerState switch
    {
        "PLAYING" => CastState.Playing,
        "PAUSED" => CastState.Paused,
        "BUFFERING" => CastState.Loading,
        "IDLE" => CastState.Stopped,
        _ => null,
    };

    /// 4 for photos, 3 for music and 1 for video: the Cast metadata types.
    private static int MetadataType(string mime) => CastKinds.Of(mime) switch
    {
        CastKind.Photo => 4,
        CastKind.Music => 3,
        _ => 1,
    };

    private static JsonObject MediaCall(string type, int requestId, long? mediaSessionId)
    {
        var call = new JsonObject { ["type"] = type, ["requestId"] = requestId };
        if (mediaSessionId is long id) call["mediaSessionId"] = id;
        return call;
    }

    private static string? Text(JsonNode? node) =>
        node is JsonValue value && value.GetValueKind() == JsonValueKind.String ? value.GetValue<string>() : null;

    private static double? Number(JsonNode? node)
    {
        if (node is not JsonValue value || value.GetValueKind() != JsonValueKind.Number) return null;

        if (value.TryGetValue<double>(out var real)) return real;
        if (value.TryGetValue<long>(out var whole)) return whole;
        return value.TryGetValue<int>(out var small) ? small : null;
    }
}

/// The Default Media Receiver running on a TV: TransportId is where media messages go.
public sealed record CastApp(string SessionId, string TransportId);

/// What a Cast TV's player reports. A null State means it reported nothing we know.
public sealed record CastMedia(long? MediaSessionId, CastState? State, CastPosition? Position);

/// One Cast message, as sent over the TLS connection in a 4-byte length frame. Only text payloads are used.
public sealed record CastMessage(string Source, string Destination, string Namespace, string Payload)
{
    /// The protobuf encoding of the message.
    public byte[] Encode()
    {
        var output = new List<byte> { 0x08, 0x00 };

        WriteString(output, 2, Source);
        WriteString(output, 3, Destination);
        WriteString(output, 4, Namespace);
        output.AddRange([0x28, 0x00]);
        WriteString(output, 6, Payload);

        return [.. output];
    }

    /// Reads a message, skipping fields it doesn't use. Null if the bytes aren't a whole message.
    public static CastMessage? Decode(byte[] bytes)
    {
        var fields = new Dictionary<int, string>();
        var at = 0;

        ulong? Varint()
        {
            ulong value = 0;
            var shift = 0;
            while (at < bytes.Length && shift < 64)
            {
                var b = bytes[at++];
                value |= (ulong)(b & 0x7f) << shift;
                if ((b & 0x80) == 0) return value;
                shift += 7;
            }
            return null;
        }

        while (at < bytes.Length)
        {
            if (Varint() is not ulong tag) return null;
            var field = (int)(tag >> 3);

            switch (tag & 7)
            {
                case 0:
                    if (Varint() is null) return null;
                    break;
                case 1:
                    at += 8;
                    break;
                case 2:
                    if (Varint() is not ulong length || length > (ulong)(bytes.Length - at)) return null;
                    fields[field] = Encoding.UTF8.GetString(bytes, at, (int)length);
                    at += (int)length;
                    break;
                case 5:
                    at += 4;
                    break;
                default:
                    return null;
            }
        }

        if (at > bytes.Length || !fields.TryGetValue(4, out var ns)) return null;

        return new CastMessage(fields.GetValueOrDefault(2) ?? "", fields.GetValueOrDefault(3) ?? "", ns, fields.GetValueOrDefault(6) ?? "");
    }

    private static void WriteString(List<byte> output, int field, string text)
    {
        var bytes = Encoding.UTF8.GetBytes(text);

        output.Add((byte)(field << 3 | 2));
        var length = bytes.Length;
        while (length >= 0x80)
        {
            output.Add((byte)(length & 0x7f | 0x80));
            length >>= 7;
        }
        output.Add((byte)length);
        output.AddRange(bytes);
    }
}

/// One record from an mDNS answer. Data is the target name (PTR), "port target" (SRV), the IPv4 address (A) or key=value lines (TXT).
public sealed record DnsRecord(string Name, int Type, IReadOnlyList<string> Data)
{
    public bool Equals(DnsRecord? other) => other is not null && Name == other.Name && Type == other.Type && Data.SequenceEqual(other.Data);

    public override int GetHashCode() => HashCode.Combine(Name, Type, Data.Count);
}

/// Multicast DNS, which Cast TVs answer to say where they are. Mirrors Mdns in GoogleCast.kt.
public static class Mdns
{
    public const string Address = "224.0.0.251";
    public const int Port = 5353;

    public const int A = 1;
    public const int Ptr = 12;
    public const int Txt = 16;
    public const int Srv = 33;

    /// A question for the service, asking for answers sent straight back to us.
    public static byte[] Query(string service = GoogleCast.Service)
    {
        var output = new List<byte> { 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 };

        foreach (var label in service.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            var bytes = Encoding.UTF8.GetBytes(label);
            output.Add((byte)bytes.Length);
            output.AddRange(bytes);
        }
        output.AddRange([0, 0, Ptr, 0x80, 0x01]);

        return [.. output];
    }

    /// The answer, authority and additional records in the packet. Empty if it's malformed or a question.
    public static List<DnsRecord> Parse(byte[] packet)
    {
        try
        {
            var reader = new DnsReader(packet);
            if ((reader.U16(2) & 0x8000) == 0) return [];

            var questions = reader.U16(4);
            var records = reader.U16(6) + reader.U16(8) + reader.U16(10);

            reader.At = 12;
            for (var i = 0; i < questions; i++)
            {
                reader.Name();
                reader.At += 4;
            }

            var found = new List<DnsRecord>();
            for (var i = 0; i < records; i++)
            {
                if (reader.Record() is DnsRecord record) found.Add(record);
            }

            return found;
        }
        catch (Exception e) when (e is IndexOutOfRangeException or ArgumentException or InvalidDataException)
        {
            return [];
        }
    }

    /// The Cast TVs in a set of records. The sender is used when there is no address record.
    public static List<TvRenderer> CastTvs(IReadOnlyList<DnsRecord> records, string sender)
    {
        var tvs = new List<TvRenderer>();

        foreach (var pointer in records.Where(r => r.Type == Ptr && string.Equals(r.Name, GoogleCast.Service, StringComparison.OrdinalIgnoreCase)))
        {
            if (pointer.Data.FirstOrDefault() is not string instance) continue;

            var location = records.FirstOrDefault(r => r.Type == Srv && Same(r.Name, instance))?.Data.FirstOrDefault()?.Split(' ', 2);
            var fields = new Dictionary<string, string>();
            foreach (var line in records.FirstOrDefault(r => r.Type == Txt && Same(r.Name, instance))?.Data ?? [])
            {
                var equals = line.IndexOf('=');
                if (equals > 0) fields[line[..equals].ToLowerInvariant()] = line[(equals + 1)..];
            }

            var port = location is { Length: > 0 } && int.TryParse(location[0], out var parsed) ? parsed : GoogleCast.Port;
            var target = location is { Length: > 1 } ? location[1] : null;
            var host = (target is null ? null : records.FirstOrDefault(r => r.Type == A && Same(r.Name, target))?.Data.FirstOrDefault()) ?? sender;
            var name = fields.GetValueOrDefault("fn") is string fn && !string.IsNullOrWhiteSpace(fn) ? fn : instance.Split('.')[0];

            tvs.Add(new TvRenderer("cast:" + (fields.GetValueOrDefault("id") ?? instance), name, Cast: new CastEndpoint(host, port)));
        }

        return tvs;
    }

    private static bool Same(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

    private sealed class DnsReader(byte[] bytes)
    {
        public int At;

        public int U8(int offset) => bytes[offset];

        public int U16(int offset) => U8(offset) << 8 | U8(offset + 1);

        public DnsRecord? Record()
        {
            var name = Name();
            var type = U16(At);
            var length = U16(At + 8);
            var start = At + 10;
            var end = start + length;
            if (end > bytes.Length) throw new InvalidDataException("record runs past the packet");

            At = start;
            List<string>? data;
            switch (type)
            {
                case Ptr:
                    data = [Name()];
                    break;
                case Srv:
                    var port = U16(start + 4);
                    At = start + 6;
                    data = [$"{port} {Name()}"];
                    break;
                case A:
                    data = length == 4 ? [string.Join('.', bytes[start..end])] : null;
                    break;
                case Txt:
                    data = [];
                    for (var i = start; i < end;)
                    {
                        var size = U8(i);
                        if (i + 1 + size > end) break;
                        data.Add(Encoding.UTF8.GetString(bytes, i + 1, size));
                        i += 1 + size;
                    }
                    break;
                default:
                    data = null;
                    break;
            }
            At = end;

            return data is null ? null : new DnsRecord(name, type, data);
        }

        /// Reads a name at At, following compression pointers.
        public string Name()
        {
            var labels = new List<string>();
            var offset = At;
            var jumped = false;
            var jumps = 0;

            while (true)
            {
                var size = U8(offset);
                if (size == 0)
                {
                    if (!jumped) At = offset + 1;
                    return string.Join('.', labels);
                }

                if ((size & 0xc0) == 0xc0)
                {
                    if (++jumps > 16) throw new InvalidDataException("name loops");
                    if (!jumped) At = offset + 2;
                    offset = (size & 0x3f) << 8 | U8(offset + 1);
                    jumped = true;
                }
                else
                {
                    labels.Add(Encoding.UTF8.GetString(bytes, offset + 1, size));
                    offset += 1 + size;
                }
            }
        }
    }
}
