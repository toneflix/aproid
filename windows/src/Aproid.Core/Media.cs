using System.Text.Json.Nodes;

namespace Aproid.Core;

/// One media player on the phone, as "kdeconnect.mpris" describes it. Times are in milliseconds.
/// Mirrors Media.kt and Media.swift.
public sealed record MediaPlayer(string Name)
{
    public string Title { get; init; } = "";

    public string Artist { get; init; } = "";

    public string Album { get; init; } = "";

    public bool IsPlaying { get; init; }

    public long Position { get; init; }

    public long Length { get; init; }

    public int? Volume { get; init; }

    public bool CanPlay { get; init; } = true;

    public bool CanPause { get; init; } = true;

    public bool CanGoNext { get; init; }

    public bool CanGoPrevious { get; init; }

    public bool CanSeek { get; init; }

    public string? AlbumArtUrl { get; init; }

    /// Null unless the packet describes a player.
    public static MediaPlayer? FromPacket(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Mpris || packet.GetBool("transferringAlbumArt") == true) return null;
        if (packet.GetString("player") is not string name) return null;

        return new MediaPlayer(name)
        {
            Title = packet.GetString("title") ?? "",
            Artist = packet.GetString("artist") ?? "",
            Album = packet.GetString("album") ?? "",
            IsPlaying = packet.GetBool("isPlaying") ?? false,
            Position = packet.GetLong("pos") ?? 0,
            Length = packet.GetLong("length") ?? 0,
            Volume = packet.GetLong("volume") is long volume ? (int)volume : null,
            CanPlay = packet.GetBool("canPlay") ?? true,
            CanPause = packet.GetBool("canPause") ?? true,
            CanGoNext = packet.GetBool("canGoNext") ?? false,
            CanGoPrevious = packet.GetBool("canGoPrevious") ?? false,
            CanSeek = packet.GetBool("canSeek") ?? false,
            AlbumArtUrl = packet.GetString("albumArtUrl") is { Length: > 0 } url ? url : null,
        };
    }

    public NetworkPacket ToPacket()
    {
        var body = new JsonObject
        {
            ["player"] = Name,
            ["title"] = Title,
            ["artist"] = Artist,
            ["album"] = Album,
            ["isPlaying"] = IsPlaying,
            ["pos"] = Position,
            ["length"] = Length,
            ["canPlay"] = CanPlay,
            ["canPause"] = CanPause,
            ["canGoNext"] = CanGoNext,
            ["canGoPrevious"] = CanGoPrevious,
            ["canSeek"] = CanSeek,
        };
        if (Volume is int volume) body["volume"] = volume;
        if (AlbumArtUrl is not null) body["albumArtUrl"] = AlbumArtUrl;

        return new NetworkPacket(PacketType.Mpris, body);
    }
}

public enum MediaAction
{
    PlayPause,
    Play,
    Pause,
    Next,
    Previous,
    Stop,
}

/// What the computer asks of the phone's players ("kdeconnect.mpris.request").
public sealed record MediaRequest(string? Player = null)
{
    public bool WantsPlayerList { get; init; }

    public bool WantsNowPlaying { get; init; }

    public MediaAction? Action { get; init; }

    public long? SeekTo { get; init; }

    public int? Volume { get; init; }

    public string? AlbumArtUrl { get; init; }

    public static MediaRequest PlayerList() => new() { WantsPlayerList = true };

    public static MediaRequest NowPlaying(string player) => new(player) { WantsNowPlaying = true };

    public static MediaRequest Act(string player, MediaAction action) => new(player) { Action = action };

    public static MediaRequest Seek(string player, long position) => new(player) { SeekTo = position };

    public static MediaRequest SetVolume(string player, int volume) => new(player) { Volume = Math.Clamp(volume, 0, 100) };

    public static MediaRequest AlbumArt(string player, string url) => new(player) { AlbumArtUrl = url };

    public static MediaRequest? FromPacket(NetworkPacket packet)
    {
        if (packet.Type != PacketType.MprisRequest) return null;

        return new MediaRequest(packet.GetString("player"))
        {
            WantsPlayerList = packet.GetBool("requestPlayerList") ?? false,
            WantsNowPlaying = packet.GetBool("requestNowPlaying") ?? false,
            Action = Enum.TryParse<MediaAction>(packet.GetString("action"), false, out var action) && Enum.IsDefined(action) ? action : null,
            SeekTo = packet.GetLong("SetPosition"),
            Volume = packet.GetLong("setVolume") is long volume ? (int)volume : null,
            AlbumArtUrl = packet.GetString("albumArtUrl"),
        };
    }

    public NetworkPacket ToPacket()
    {
        var body = new JsonObject();
        if (Player is not null) body["player"] = Player;
        if (WantsPlayerList) body["requestPlayerList"] = true;
        if (WantsNowPlaying)
        {
            body["requestNowPlaying"] = true;
            body["requestVolume"] = true;
        }
        if (Action is MediaAction action) body["action"] = action.ToString();
        if (SeekTo is long seekTo) body["SetPosition"] = seekTo;
        if (Volume is int volume) body["setVolume"] = volume;
        if (AlbumArtUrl is not null) body["albumArtUrl"] = AlbumArtUrl;

        return new NetworkPacket(PacketType.MprisRequest, body);
    }
}

/// The other "kdeconnect.mpris" packets: the list of players, and album art sent as a payload.
public static class Media
{
    public static NetworkPacket PlayerListPacket(IEnumerable<string> names) => new(PacketType.Mpris, new JsonObject
    {
        ["playerList"] = new JsonArray(names.Select(name => (JsonNode?)name).ToArray()),
        ["supportAlbumArtPayload"] = true,
    });

    /// The player names, or null if the packet has no list.
    public static IReadOnlyList<string>? PlayerList(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Mpris || !packet.Body.ContainsKey("playerList")) return null;

        return packet.GetStringList("playerList");
    }

    /// Announces album art for `url`. Send it with Device.SendWithPayload.
    public static NetworkPacket AlbumArtPacket(string player, string url) => new(PacketType.Mpris, new JsonObject
    {
        ["player"] = player,
        ["albumArtUrl"] = url,
        ["transferringAlbumArt"] = true,
    });

    /// The art's url when the packet carries album art.
    public static string? AlbumArtUrl(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Mpris || packet.GetBool("transferringAlbumArt") != true) return null;

        return packet.GetString("albumArtUrl");
    }
}
