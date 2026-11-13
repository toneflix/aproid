using Aproid.Core;

namespace Aproid.Core.Tests;

/// Packets in the shapes KDE Connect itself sends (protocol v8). KdeConnectFormatTest.kt and the Swift tests check the same.
public class KdeConnectFormatTests
{
    private static NetworkPacket Parse(string wire) => NetworkPacket.Parse(wire);

    private static HashSet<string> Keys(NetworkPacket packet) => NetworkPacket.Parse(packet.Serialize()).Body.Select(pair => pair.Key).ToHashSet();

    [Fact]
    public void ReadsKdeNotification()
    {
        // KDE sends the time as a string and an empty requestReplyId when there is no reply.
        var packet = Parse("""{"id":1,"type":"kdeconnect.notification","body":{"id":"0|org.telegram|7|null|10234","appName":"Telegram","ticker":"Ann: hi","isClearable":true,"title":"Ann","text":"hi","time":"1700000000000","silent":"false","requestReplyId":"","actions":["Mark as read"]}}""");

        var notification = PhoneNotification.FromPacket(packet)!;

        Assert.Equal("0|org.telegram|7|null|10234", notification.Id);
        Assert.Equal(1_700_000_000_000, notification.Time);
        Assert.Null(notification.ReplyId);
        Assert.Equal(["Mark as read"], notification.ActionTitles);
        Assert.Equal("0|org.telegram|7|null|10234", PhoneNotification.CancelledId(Parse("""{"id":2,"type":"kdeconnect.notification","body":{"id":"0|org.telegram|7|null|10234","isCancel":true}}""")));
    }

    [Fact]
    public void WritesKdeNotificationFields()
    {
        var sent = Keys(new PhoneNotification("k", "Signal", "Bo", "hi", 1, ReplyId: "r1").ToPacket());

        Assert.Superset(new HashSet<string> { "id", "appName", "title", "text", "ticker", "time", "isClearable", "requestReplyId" }, sent);
        Assert.Equal(["requestReplyId", "message"], Keys(NotificationRequests.Reply("r1", "ok")));
        Assert.Equal(["cancel"], Keys(NotificationRequests.Dismiss("k")));
        Assert.Equal(["request"], Keys(NotificationRequests.RequestAll()));
        Assert.Equal(["key", "action"], Keys(NotificationRequests.Action("k", "Archive")));
    }

    [Fact]
    public void NotificationActionsRoundTrip()
    {
        var sent = new PhoneNotification("k", "Gmail", "Bo", "hi", 1, Actions: ["Archive", "Reply"]).ToPacket();

        Assert.Equal(["Archive", "Reply"], PhoneNotification.FromPacket(NetworkPacket.Parse(sent.Serialize()))!.ActionTitles);
        Assert.Equal(new NotificationAction("k", "Archive"), NotificationAction.FromPacket(NetworkPacket.Parse(NotificationRequests.Action("k", "Archive").Serialize())));
        Assert.Null(NotificationAction.FromPacket(NetworkPacket.Parse("""{"id":1,"type":"kdeconnect.notification.action","body":{"key":"k"}}""")));
    }

    [Fact]
    public void IconHashIsLowercaseMd5()
    {
        Assert.Equal("900150983cd24fb0d6963f7d28e17f72", PhoneNotification.HashIcon("abc"u8.ToArray()));
    }

    [Fact]
    public void ReadsKdeShares()
    {
        var file = Parse("""{"id":1,"type":"kdeconnect.share.request","body":{"filename":"IMG_1.jpg","lastModified":1700000000000,"numberOfFiles":1,"totalPayloadSize":2048},"payloadSize":2048,"payloadTransferInfo":{"port":1739}}""");

        Assert.Equal(new Share.File("IMG_1.jpg", 2048), Share.FromPacket(file));
        Assert.Equal(1739, file.PayloadPort);
        Assert.Equal(new Share.Link("https://kde.org"), Share.FromPacket(Parse("""{"id":1,"type":"kdeconnect.share.request","body":{"url":"https://kde.org"}}""")));
        Assert.Equal(new Share.Text("hello"), Share.FromPacket(Parse("""{"id":1,"type":"kdeconnect.share.request","body":{"text":"hello"}}""")));
    }

    [Fact]
    public void ResumableFilesCarryTheirTransfer()
    {
        var packet = Share.FilePacket("a.bin", 100, transferId: "t1", offset: 40);
        packet.PayloadSize = 60;

        Assert.Equal(new Share.File("a.bin", 60, "t1", 40), Share.FromPacket(packet));
        Assert.Equal(("t1", 40L), Share.ResumeRequest(Share.ResumePacket("t1", 40)));
    }

    [Fact]
    public void SafeNamesStayInTheFolder()
    {
        Assert.Equal("passwd", Share.SafeName("../../etc/passwd"));
        Assert.Equal("evil.exe", Share.SafeName("..\\..\\Windows\\evil.exe"));
        Assert.Equal("file", Share.SafeName(".."));
        Assert.Equal("ab.txt", Share.SafeName("a:b.txt"));
    }

    [Fact]
    public void ReadsKdeClipboardBatteryAndPairing()
    {
        Assert.Equal("copied", Clipboard.Content(Parse("""{"id":1,"type":"kdeconnect.clipboard","body":{"content":"copied"}}""")));
        Assert.Equal("copied", Clipboard.Content(Parse("""{"id":1,"type":"kdeconnect.clipboard.connect","body":{"content":"copied","timestamp":1700000000000}}""")));
        Assert.Equal(new BatteryStatus(9, false, true), BatteryStatus.FromPacket(Parse("""{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":9,"isCharging":false,"thresholdEvent":1}}""")));

        var request = new PairingStateMachine().RequestPair(1_700_000_000);
        Assert.Equal(["pair", "timestamp"], Keys(request.Packet!));

        // KDE Connect v8 pairs with a timestamp in seconds.
        var peer = new PairingStateMachine();
        peer.Handle(Parse("""{"id":1,"type":"kdeconnect.pair","body":{"pair":true,"timestamp":1700000000}}"""), 1_700_000_010);
        Assert.Equal(PairState.RequestedByPeer, peer.State);
    }

    [Fact]
    public void OurOwnPacketsAreNamespacedAndAdvertised()
    {
        Assert.All(Capabilities.Mvp, type => Assert.True(type.StartsWith("kdeconnect.") || type.StartsWith("flyylink.")));
        Assert.Superset(new HashSet<string>
        {
            PacketType.Photos, PacketType.PhotosRequest, PacketType.PhotosDownload, PacketType.PhotosFile,
            PacketType.Screen, PacketType.ScreenRequest, PacketType.ScreenInput,
            PacketType.Location, PacketType.LocationRequest, PacketType.ShareResume,
            PacketType.ClipboardFile, PacketType.CallRequest, PacketType.Heartbeat,
        }, Capabilities.Mvp.ToHashSet());
    }

    [Fact]
    public void ReadsKdeTelephony()
    {
        var ringing = Call.StateOf(Parse("""{"id":1,"type":"kdeconnect.telephony","body":{"event":"ringing","phoneNumber":"+2348000000000","contactName":"Ann","phoneThumbnail":"aGk="}}"""))!;
        var ended = Call.StateOf(Parse("""{"id":2,"type":"kdeconnect.telephony","body":{"event":"ringing","phoneNumber":"+2348000000000","isCancel":true}}"""))!;

        Assert.Equal(CallEvent.Ringing, ringing.Event);
        Assert.Equal("Ann", ringing.ContactName);
        Assert.True(ended.Ended);
        Assert.Equal(["event", "phoneNumber", "contactName"], Keys(Call.Event(CallEvent.Talking, "1", "Bo")));
    }

    [Fact]
    public void ReadsKdeSms()
    {
        var message = Sms.Messages(Parse("""{"id":1,"type":"kdeconnect.sms.messages","body":{"version":2,"messages":[{"_id":"41","thread_id":"7","body":"hi","addresses":[{"address":"+2348000000000"}],"date":"1700000000000","type":"1","read":"0","event":1,"sub_id":1}]}}"""))![0];

        Assert.Equal(41, message.Id);
        Assert.Equal(7, message.ThreadId);
        Assert.True(message.IsIncoming);
        Assert.False(message.IsRead);

        // KDE's desktop sends version 2 with an address list; older apps sent one phoneNumber.
        var v2 = Sms.SendRequestOf(Parse("""{"id":1,"type":"kdeconnect.sms.request","body":{"version":2,"addresses":[{"address":"555"}],"messageBody":"yo","subID":-1}}"""))!;
        var v1 = Sms.SendRequestOf(Parse("""{"id":1,"type":"kdeconnect.sms.request","body":{"sendSms":true,"phoneNumber":"555","messageBody":"yo"}}"""))!;
        Assert.Equal(["555"], v2.Addresses);
        Assert.Equal(["555"], v1.Addresses);

        var asked = Sms.ConversationRequestOf(Parse("""{"id":1,"type":"kdeconnect.sms.request_conversation","body":{"threadID":7,"rangeStartTimestamp":1700000000000,"numberToRequest":20}}"""))!;
        Assert.Equal(7, asked.ThreadId);
    }

    [Fact]
    public void ReadsKdeMedia()
    {
        var player = MediaPlayer.FromPacket(Parse("""{"id":1,"type":"kdeconnect.mpris","body":{"player":"Spotify","title":"Song","artist":"Band","album":"LP","isPlaying":true,"pos":1000,"length":200000,"volume":70,"canPlay":true,"canPause":true,"canGoNext":true,"canGoPrevious":true,"canSeek":true}}"""))!;
        var request = MediaRequest.FromPacket(Parse("""{"id":1,"type":"kdeconnect.mpris.request","body":{"player":"Spotify","action":"PlayPause"}}"""))!;

        Assert.Equal("Song", player.Title);
        Assert.Equal(200_000, player.Length);
        Assert.Equal(MediaAction.PlayPause, request.Action);
        Assert.Contains("SetPosition", Keys(MediaRequest.Seek("Spotify", 5000).ToPacket()));
    }
}
