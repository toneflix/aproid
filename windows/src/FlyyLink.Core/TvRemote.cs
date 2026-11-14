using System.Text.Json.Nodes;

namespace FlyyLink.Core;

/// A press on the remote a phone shows for a TV ("flyylink.remote"): a key, or text typed into the TV's
/// focused field. Mirrors TvRemote.kt and TvRemote.swift.
public abstract record TvRemote
{
    public const string Up = "up";
    public const string Down = "down";
    public const string Left = "left";
    public const string Right = "right";
    public const string Select = "select";
    public const string Back = "back";
    public const string Home = "home";
    public const string Menu = "menu";
    public const string PlayPause = "playPause";
    public const string Next = "next";
    public const string Previous = "previous";
    public const string VolumeUp = "volumeUp";
    public const string VolumeDown = "volumeDown";
    public const string Mute = "mute";
    public const string Delete = "delete";
    public const string Enter = "enter";

    public static readonly IReadOnlySet<string> Keys = new HashSet<string>
    {
        Up, Down, Left, Right, Select, Back, Home, Menu, PlayPause, Next, Previous, VolumeUp, VolumeDown, Mute, Delete, Enter,
    };

    /// Longer text than this in one packet is treated as nonsense.
    public const int MaxText = 1000;

    public sealed record Key(string Name) : TvRemote;

    public sealed record Text(string Value) : TvRemote;

    public NetworkPacket ToPacket()
    {
        var body = this switch
        {
            Key key => new JsonObject { ["action"] = "key", ["key"] = key.Name },
            Text text => new JsonObject { ["action"] = "text", ["text"] = text.Value },
            _ => throw new InvalidOperationException(),
        };

        return new NetworkPacket(PacketType.Remote, body);
    }

    public static TvRemote? FromPacket(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Remote) return null;

        return packet.GetString("action") switch
        {
            "key" when packet.GetString("key") is string key && Keys.Contains(key) => new Key(key),
            "text" when packet.GetString("text") is { Length: > 0 and <= MaxText } text => new Text(text),
            _ => null,
        };
    }
}
