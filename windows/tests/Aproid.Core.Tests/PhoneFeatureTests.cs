using Aproid.Core;

namespace Aproid.Core.Tests;

/// Messages, calls, media, photos, location and device focus. Mirrors the Swift and Kotlin tests of the same names.
public class PhoneFeatureTests
{
    private static NetworkPacket Wire(NetworkPacket packet) => NetworkPacket.Parse(packet.Serialize());

    private static readonly SmsMessage Message = new(
        41,
        7,
        "Running late, 10 min",
        [new SmsAddress("+2348012345678", "Ada")],
        1_700_000_000_000,
        IsIncoming: true,
        IsRead: false,
        SubscriptionId: 1,
        Attachments: [new SmsAttachment(3, "image/jpeg", "part-3", "aGVsbG8=")]);

    [Fact]
    public void SmsMessagesRoundTrip()
    {
        var sent = Message with { Id = 42, Body = "No worries", IsIncoming = false, IsRead = true, Attachments = [] };

        Assert.Equivalent(new[] { Message, sent }, Sms.Messages(Wire(Sms.MessagesPacket([Message, sent]))), strict: true);
    }

    [Fact]
    public void ReadsKdeConnectSmsMessage()
    {
        var packet = NetworkPacket.Parse("""{"id":1,"type":"kdeconnect.sms.messages","body":{"version":2,"messages":[{"_id":"5","thread_id":2,"body":"hi","date":1700000000000,"type":2,"read":1,"event":1,"addresses":[{"address":"555"}]}]}}""");

        var read = Assert.Single(Sms.Messages(packet)!);

        Assert.Equal(5, read.Id);
        Assert.False(read.IsIncoming);
        Assert.Equal([new SmsAddress("555")], read.Addresses);
    }

    [Fact]
    public void SmsRequestsRoundTrip()
    {
        Assert.Equal(new Sms.ConversationRequest(7, 1_700_000_000_000, 30), Sms.ConversationRequestOf(Wire(Sms.RequestConversation(7, 1_700_000_000_000, 30))));
        Assert.Equal(new Sms.ConversationRequest(7, null, 50), Sms.ConversationRequestOf(Wire(Sms.RequestConversation(7))));

        var send = Sms.SendRequestOf(Wire(Sms.Send(["+234801", "+234802"], "On my way", 2)))!;
        Assert.Equal(["+234801", "+234802"], send.Addresses);
        Assert.Equal("On my way", send.Body);
        Assert.Equal(2, send.SubscriptionId);
        Assert.Equal(PacketType.SmsRequestConversations, Sms.RequestConversations().Type);
    }

    [Fact]
    public void ReadsVersionOneSmsSendRequest()
    {
        var packet = NetworkPacket.Parse("""{"id":1,"type":"kdeconnect.sms.request","body":{"phoneNumber":"555","messageBody":"yo"}}""");

        var send = Sms.SendRequestOf(packet)!;

        Assert.Equal(["555"], send.Addresses);
        Assert.Null(send.SubscriptionId);
        Assert.Null(Sms.Messages(packet));
    }

    [Fact]
    public void CallEventsRoundTrip()
    {
        Assert.Equal(
            new Call.State(CallEvent.Ringing, "+2348012345678", "Ada", "aGVsbG8="),
            Call.StateOf(Wire(Call.Event(CallEvent.Ringing, "+2348012345678", "Ada", "aGVsbG8="))));
        Assert.Equal(new Call.State(CallEvent.Ringing, "555", Ended: true), Call.StateOf(Wire(Call.Ended("555"))));
    }

    [Fact]
    public void ReadsKdeConnectMissedCall()
    {
        var packet = NetworkPacket.Parse("""{"id":1,"type":"kdeconnect.telephony","body":{"event":"missedCall","phoneNumber":"555","contactName":"Bo"}}""");

        Assert.Equal(new Call.State(CallEvent.Missed, "555", "Bo"), Call.StateOf(packet));
    }

    [Fact]
    public void CallRequestsRoundTrip()
    {
        Assert.Equal(new Call.Request(Call.Action.Answer), Call.RequestOf(Wire(Call.Answer())));
        Assert.Equal(new Call.Request(Call.Action.Decline), Call.RequestOf(Wire(Call.Decline())));
        Assert.Equal(new Call.Request(Call.Action.HangUp), Call.RequestOf(Wire(Call.HangUp())));
        Assert.Equal(new Call.Request(Call.Action.Mute), Call.RequestOf(Wire(Call.Mute(true))));
        Assert.Equal(new Call.Request(Call.Action.Unmute), Call.RequestOf(Wire(Call.Mute(false))));
        Assert.Equal(new Call.Request(Call.Action.Dial, "+234801"), Call.RequestOf(Wire(Call.Dial("+234801"))));
    }

    [Fact]
    public void DialNeedsANumber()
    {
        Assert.Null(Call.RequestOf(Wire(Call.Dial(" "))));
        Assert.Null(Call.StateOf(Wire(Call.Answer())));
    }

    private static readonly MediaPlayer Player = new("Spotify")
    {
        Title = "Midnight City",
        Artist = "M83",
        Album = "Hurry Up, We're Dreaming",
        IsPlaying = true,
        Position = 61_000,
        Length = 243_000,
        Volume = 70,
        CanGoNext = true,
        CanGoPrevious = true,
        CanSeek = true,
        AlbumArtUrl = "aproid://art/1f2e",
    };

    [Fact]
    public void MediaPlayerRoundTrips()
    {
        Assert.Equal(Player, MediaPlayer.FromPacket(Wire(Player.ToPacket())));
    }

    [Fact]
    public void MediaRequestsRoundTrip()
    {
        MediaRequest[] requests =
        [
            MediaRequest.PlayerList(),
            MediaRequest.NowPlaying("Spotify"),
            MediaRequest.Act("Spotify", MediaAction.Next),
            MediaRequest.Seek("Spotify", 90_000),
            MediaRequest.SetVolume("Spotify", 140),
            MediaRequest.AlbumArt("Spotify", "aproid://art/1f2e"),
        ];

        foreach (var request in requests) Assert.Equal(request, MediaRequest.FromPacket(Wire(request.ToPacket())));
        Assert.Equal(100, MediaRequest.SetVolume("Spotify", 140).Volume);
    }

    [Fact]
    public void ReadsKdeConnectMediaRequest()
    {
        var packet = NetworkPacket.Parse("""{"id":1,"type":"kdeconnect.mpris.request","body":{"player":"VLC","action":"PlayPause"}}""");

        var request = MediaRequest.FromPacket(packet)!;

        Assert.Equal("VLC", request.Player);
        Assert.Equal(MediaAction.PlayPause, request.Action);
    }

    [Fact]
    public void PlayerListAndAlbumArtAreNotPlayers()
    {
        var list = Wire(Media.PlayerListPacket(["Spotify", "YouTube Music"]));
        var art = Wire(Media.AlbumArtPacket("Spotify", "aproid://art/1f2e"));

        Assert.Equal(["Spotify", "YouTube Music"], Media.PlayerList(list));
        Assert.Null(MediaPlayer.FromPacket(list));
        Assert.Null(MediaPlayer.FromPacket(art));
        Assert.Null(Media.PlayerList(Player.ToPacket()));
        Assert.Equal("aproid://art/1f2e", Media.AlbumArtUrl(art));
    }

    [Fact]
    public void PhotosPageRoundTrips()
    {
        PhonePhoto[] photos =
        [
            new(12, "IMG_2041.jpg", 1_700_000_000_000, "image/jpeg", 4000, 3000, 2_400_000, "aGVsbG8="),
            new(13, "VID_0007.mp4", 1_700_000_100_000, "video/mp4"),
        ];

        var page = Photos.PageOf(Wire(Photos.PagePacket(photos, more: true)))!;

        Assert.Equal(photos, page.Items);
        Assert.True(page.More);
        Assert.True(photos[1].IsVideo);
    }

    [Fact]
    public void PhotosRequestsRoundTrip()
    {
        Assert.Equal(new Photos.Request(1_700_000_000_000, 40), Photos.RequestOf(Wire(Photos.RequestPacket(1_700_000_000_000))));
        Assert.Equal(new Photos.Request(null, 200), Photos.RequestOf(Wire(Photos.RequestPacket(count: 5000))));
        Assert.Equal(new Photos.Download(12, false), Photos.DownloadOf(Wire(Photos.DownloadPacket(12))));
        Assert.Equal(new Photos.Download(12, true), Photos.DownloadOf(Wire(Photos.DownloadPacket(12, preview: true))));
        Assert.Null(Photos.DownloadOf(Photos.RequestPacket()));
    }

    [Fact]
    public void PhotoPreviewFileRoundTrips()
    {
        var file = new Photos.File(12, "IMG_2041.heic", "image/heic");

        Assert.Equal(file, Photos.FileOf(Wire(Photos.FilePacket(file))));
        Assert.Null(Photos.FileOf(Photos.DownloadPacket(12)));
    }

    [Fact]
    public void LocationRoundTripsAndRejectsNonsense()
    {
        var here = new PhoneLocation(6.5244, 3.3792, 12.5, 1_700_000_000_000);

        Assert.Equal(here, PhoneLocation.FromPacket(Wire(here.ToPacket())));
        Assert.Null(PhoneLocation.FromPacket(new PhoneLocation(95, 3, 1, 0).ToPacket()));
        Assert.Equal(PacketType.LocationRequest, PhoneLocation.Request().Type);
    }

    private sealed record Peer(string Id, string Name);

    private static readonly Peer[] Peers = [new("c", "Pixel"), new("a", "Galaxy"), new("b", "Pixel")];

    private static Peer? Pick(string? preferredId, Peer[]? list = null) =>
        new DeviceFocus(preferredId).Pick(list ?? Peers, peer => peer.Id, peer => peer.Name);

    [Fact]
    public void PreferredDeviceWins() => Assert.Equal(new Peer("c", "Pixel"), Pick("c"));

    [Fact]
    public void FocusFallsBackToFirstByName() => Assert.Equal(new Peer("a", "Galaxy"), Pick(null));

    [Fact]
    public void MissingPreferredDeviceFallsBack() => Assert.Equal(new Peer("a", "Galaxy"), Pick("gone"));

    [Fact]
    public void SameNamesAreOrderedById() => Assert.Equal(new Peer("b", "Pixel"), Pick(null, [new("c", "Pixel"), new("b", "Pixel")]));

    [Fact]
    public void NoDevicesPicksNothing() => Assert.Null(Pick("a", []));
}
