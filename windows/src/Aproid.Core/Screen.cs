using System.Buffers.Binary;
using System.Text.Json.Nodes;

namespace Aproid.Core;

/// Mirroring the phone's screen. The computer asks with `Start`; the phone answers with an "aproid.screen" packet
/// whose payload is a live H.264 stream of `ScreenFrame`s. Mirrors Screen.kt and Screen.swift.
public static class Screen
{
    /// The payload size of a live stream: read until the sender closes it.
    public const long Stream = -1;

    public const long MaxSize = 1600;
    public const long Bitrate = 8_000_000;

    public enum Action
    {
        Start,
        Stop,
    }

    public sealed record Request(Action Action, long MaxSize = Screen.MaxSize, long Bitrate = Screen.Bitrate);

    /// What the phone is sending. Sizes are in pixels; `Running` is false once mirroring stops.
    public sealed record Info(long Width, long Height, bool Running);

    public static NetworkPacket Start(long maxSize = MaxSize, long bitrate = Bitrate) => new(PacketType.ScreenRequest, new JsonObject
    {
        ["action"] = "start",
        ["maxSize"] = maxSize,
        ["bitrate"] = bitrate,
    });

    public static NetworkPacket Stop() => new(PacketType.ScreenRequest, new JsonObject { ["action"] = "stop" });

    public static Request? RequestOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.ScreenRequest) return null;

        Action? action = packet.GetString("action") switch
        {
            "start" => Action.Start,
            "stop" => Action.Stop,
            _ => null,
        };
        if (action is not Action known) return null;

        return new Request(
            known,
            Math.Clamp(packet.GetLong("maxSize") ?? MaxSize, 320, 4096),
            Math.Clamp(packet.GetLong("bitrate") ?? Bitrate, 500_000, 50_000_000));
    }

    /// Announces a stream; send it with `Stream` as the payload size.
    public static NetworkPacket Started(long width, long height) => new(PacketType.Screen, new JsonObject
    {
        ["width"] = width,
        ["height"] = height,
        ["codec"] = "h264",
        ["running"] = true,
    });

    public static NetworkPacket Stopped() => new(PacketType.Screen, new JsonObject { ["running"] = false });

    public static Info? InfoOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Screen) return null;

        return new Info(packet.GetLong("width") ?? 0, packet.GetLong("height") ?? 0, packet.GetBool("running") ?? false);
    }
}

/// One encoded piece of the screen stream. On the wire each is a 13 byte header (size, then the presentation time
/// in microseconds, then `Flags`, all big-endian) followed by H.264 in Annex B form.
public sealed record ScreenFrame(byte[] Data, long TimeUs, byte Flags)
{
    public const int HeaderSize = 13;
    public const byte Config = 1;
    public const byte Key = 2;

    /// Larger than any real frame; anything bigger means the stream is corrupt.
    public const int MaxSize = 16 * 1024 * 1024;

    /// The SPS and PPS the decoder needs before any picture.
    public bool IsConfig => (Flags & Config) != 0;

    public bool IsKey => (Flags & Key) != 0;

    public byte[] Header()
    {
        var header = new byte[HeaderSize];
        BinaryPrimitives.WriteUInt32BigEndian(header, (uint)Data.Length);
        BinaryPrimitives.WriteInt64BigEndian(header.AsSpan(4), TimeUs);
        header[12] = Flags;

        return header;
    }

    public bool Equals(ScreenFrame? other) => other is not null && TimeUs == other.TimeUs && Flags == other.Flags && Data.AsSpan().SequenceEqual(other.Data);

    public override int GetHashCode() => HashCode.Combine(Data.Length, TimeUs, Flags);
}

/// Collects stream bytes, however they are split, back into whole frames. Mirrors ScreenFrame.Reader.
public sealed class ScreenFrameReader
{
    private byte[] pending = [];

    public IReadOnlyList<ScreenFrame> Feed(ReadOnlySpan<byte> bytes)
    {
        var buffer = new byte[pending.Length + bytes.Length];
        pending.CopyTo(buffer, 0);
        bytes.CopyTo(buffer.AsSpan(pending.Length));

        var frames = new List<ScreenFrame>();
        var offset = 0;
        while (buffer.Length - offset >= ScreenFrame.HeaderSize)
        {
            var size = BinaryPrimitives.ReadUInt32BigEndian(buffer.AsSpan(offset));
            if (size > ScreenFrame.MaxSize) throw new ProtocolException($"screen frame of {size} bytes");

            var start = offset + ScreenFrame.HeaderSize;
            if (buffer.Length - start < size) break;

            var time = BinaryPrimitives.ReadInt64BigEndian(buffer.AsSpan(offset + 4));
            frames.Add(new ScreenFrame(buffer.AsSpan(start, (int)size).ToArray(), time, buffer[offset + 12]));
            offset = start + (int)size;
        }

        pending = buffer.AsSpan(offset).ToArray();

        return frames;
    }
}

/// A touch, key or typed text for the mirrored screen. Positions are fractions of the screen, 0 to 1 from the top left.
/// Mirrors ScreenInput in Screen.kt and Screen.swift.
public abstract record ScreenInput
{
    public const string Back = "back";
    public const string Home = "home";
    public const string Recents = "recents";
    public const string Notifications = "notifications";
    public const string Enter = "enter";
    public const string Delete = "delete";

    public static readonly IReadOnlySet<string> Keys = new HashSet<string> { Back, Home, Recents, Notifications, Enter, Delete };

    public sealed record Tap(double X, double Y) : ScreenInput;

    public sealed record LongPress(double X, double Y) : ScreenInput;

    public sealed record Swipe(double X, double Y, double ToX, double ToY, long DurationMs) : ScreenInput;

    public sealed record Text(string Value) : ScreenInput;

    public sealed record KeyPress(string Name) : ScreenInput;

    public NetworkPacket ToPacket()
    {
        var body = this switch
        {
            Tap tap => new JsonObject { ["action"] = "tap", ["x"] = tap.X, ["y"] = tap.Y },
            LongPress press => new JsonObject { ["action"] = "longPress", ["x"] = press.X, ["y"] = press.Y },
            Swipe swipe => new JsonObject { ["action"] = "swipe", ["x"] = swipe.X, ["y"] = swipe.Y, ["toX"] = swipe.ToX, ["toY"] = swipe.ToY, ["duration"] = swipe.DurationMs },
            Text text => new JsonObject { ["action"] = "text", ["text"] = text.Value },
            KeyPress key => new JsonObject { ["action"] = "key", ["key"] = key.Name },
            _ => throw new InvalidOperationException(),
        };

        return new NetworkPacket(PacketType.ScreenInput, body);
    }

    public static ScreenInput? FromPacket(NetworkPacket packet)
    {
        if (packet.Type != PacketType.ScreenInput) return null;

        double? Fraction(string key) => packet.GetDouble(key) is double value and >= 0 and <= 1 ? value : null;

        return packet.GetString("action") switch
        {
            "tap" when Fraction("x") is double x && Fraction("y") is double y => new Tap(x, y),
            "longPress" when Fraction("x") is double x && Fraction("y") is double y => new LongPress(x, y),
            "swipe" when Fraction("x") is double x && Fraction("y") is double y && Fraction("toX") is double toX && Fraction("toY") is double toY =>
                new Swipe(x, y, toX, toY, Math.Clamp(packet.GetLong("duration") ?? 200, 10, 5000)),
            "text" when packet.GetString("text") is { Length: > 0 } text => new Text(text),
            "key" when packet.GetString("key") is string key && Keys.Contains(key) => new KeyPress(key),
            _ => null,
        };
    }
}
