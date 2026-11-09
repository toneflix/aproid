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
        Assert.All(Capabilities.Mvp, type => Assert.True(type.StartsWith("kdeconnect.") || type.StartsWith("aproid.")));
        Assert.Superset(new HashSet<string>
        {
            PacketType.Photos, PacketType.PhotosRequest, PacketType.PhotosDownload, PacketType.PhotosFile,
            PacketType.Screen, PacketType.ScreenRequest, PacketType.ScreenInput,
            PacketType.Location, PacketType.LocationRequest, PacketType.ShareResume,
            PacketType.ClipboardFile, PacketType.CallRequest, PacketType.Heartbeat,
        }, Capabilities.Mvp.ToHashSet());
    }
}
