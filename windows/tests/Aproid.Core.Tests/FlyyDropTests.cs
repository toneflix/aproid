using Aproid.Core;

namespace Aproid.Core.Tests;

/// Mirrors FlyyDropTest.kt and FlyyDropTests.swift.
public class FlyyDropTests
{
    private long now = 1_000_000;
    private readonly FlyyDrop sender;
    private readonly FlyyDrop receiver;
    private readonly FlyyDrop.Item photo = new("photo.jpg", 2048);
    private readonly FlyyDrop.Item notes = new("notes.txt", 10);

    public FlyyDropTests()
    {
        sender = new FlyyDrop(() => now);
        receiver = new FlyyDrop(() => now) { ReceivingMode = FlyyDrop.Receiving.Everyone };
    }

    private static NetworkPacket Wire(NetworkPacket packet) => NetworkPacket.Parse(packet.Serialize());

    /// The sender asks the receiver, as it would over the network, and returns the receiver's view.
    private FlyyDrop.Offer Ask(IReadOnlyList<FlyyDrop.Item>? items = null, string? text = null)
    {
        var request = sender.Request("receiver", items ?? [photo, notes], text);
        Assert.True(sender.AdmitsOutgoing("receiver", request));
        Assert.True(receiver.AdmitsIncoming("sender", Wire(request)));

        var incoming = receiver.OnRequest("sender", Wire(request), isPaired: false);
        return Assert.IsType<FlyyDrop.Incoming.Ask>(incoming).Offer;
    }

    private void Accept(FlyyDrop.Offer offer)
    {
        var response = receiver.Accept(offer.Id)!;
        Assert.True(receiver.AdmitsOutgoing("sender", response));
        Assert.True(sender.AdmitsIncoming("receiver", Wire(response)));
        Assert.True(sender.OnResponse("receiver", Wire(response))!.Accepted);
    }

    /// A file as it arrives: the sender's packet with the payload size added.
    private static NetworkPacket Arriving(string id, FlyyDrop.Item item, long? size = null)
    {
        var packet = FlyyDrop.File(id, item);
        packet.PayloadSize = size ?? item.Size;

        return Wire(packet);
    }

    [Fact]
    public void RequestRoundTrips()
    {
        var offer = Ask();

        Assert.Equal([photo, notes], offer.Items);
        Assert.Equal(2058, offer.TotalSize);
        Assert.Equal("sender", offer.DeviceId);
    }

    [Fact]
    public void AcceptedFilesComeInOnceEach()
    {
        var offer = Ask();
        Accept(offer);

        Assert.True(sender.AdmitsOutgoing("receiver", FlyyDrop.File(offer.Id, photo)));
        Assert.True(receiver.AdmitsIncoming("sender", Arriving(offer.Id, photo)));
        Assert.False(receiver.AdmitsIncoming("sender", Arriving(offer.Id, photo)));
        Assert.True(receiver.AdmitsIncoming("sender", Arriving(offer.Id, notes)));
        Assert.False(receiver.IsActive(offer.Id));
    }

    [Fact]
    public void NothingComesInBeforeAccepting()
    {
        var offer = Ask();

        Assert.False(receiver.AdmitsIncoming("sender", Arriving(offer.Id, photo)));
        Assert.False(sender.AdmitsOutgoing("receiver", FlyyDrop.File(offer.Id, photo)));
    }

    [Fact]
    public void OnlyTheDeclaredFilesAndSizesComeIn()
    {
        var offer = Ask();
        Accept(offer);

        var plain = Share.FilePacket(photo.Name, photo.Size);
        plain.PayloadSize = photo.Size;

        Assert.False(receiver.AdmitsIncoming("sender", Arriving(offer.Id, new FlyyDrop.Item("other.exe", 2048))));
        Assert.False(receiver.AdmitsIncoming("sender", Arriving(offer.Id, photo, size: 1_000_000)));
        Assert.False(receiver.AdmitsIncoming("someone-else", Arriving(offer.Id, photo)));
        Assert.False(receiver.AdmitsIncoming("sender", Wire(plain)));
    }

    [Fact]
    public void GuestsGetNoOtherPackets()
    {
        Ask();

        Assert.False(receiver.AdmitsIncoming("sender", Clipboard.Packet("hi")));
        Assert.False(receiver.AdmitsIncoming("sender", FindMyPhone.Request()));
        Assert.False(receiver.AdmitsIncoming("sender", Share.TextPacket("hi")));
        Assert.False(receiver.AdmitsOutgoing("sender", NotificationRequests.Reply("r1", "hi")));
    }

    [Fact]
    public void AcceptedLinkComesInOnce()
    {
        var offer = Ask(items: [], text: "https://toneflix.net");
        Accept(offer);

        var link = FlyyDrop.Text(offer.Id, "https://toneflix.net");
        Assert.Equal(new Share.Link("https://toneflix.net"), Share.FromPacket(link));
        Assert.True(receiver.AdmitsIncoming("sender", Wire(link)));
        Assert.False(receiver.AdmitsIncoming("sender", Wire(link)));
        Assert.Equal(new Share.Text("hello there"), Share.FromPacket(FlyyDrop.Text("x", "hello there")));
    }

    [Fact]
    public void DeclineEndsTheRequestOnBothSides()
    {
        var offer = Ask();
        var response = receiver.Decline(offer.Id)!;

        Assert.True(receiver.AdmitsOutgoing("sender", response));
        var answer = sender.OnResponse("receiver", Wire(response))!;
        Assert.False(answer.Accepted);
        Assert.Equal(FlyyDrop.Reason.Declined, answer.Reason);
        Assert.False(sender.IsActive(offer.Id));
        Assert.False(receiver.IsActive(offer.Id));
    }

    [Fact]
    public void OffDeclinesStrangersButAsksPairedDevices()
    {
        receiver.ReceivingMode = FlyyDrop.Receiving.Off;
        var request = Wire(sender.Request("receiver", [photo]));

        var reply = Assert.IsType<FlyyDrop.Incoming.Reply>(receiver.OnRequest("sender", request, isPaired: false));
        Assert.Equal(FlyyDrop.Reason.Unavailable, sender.OnResponse("receiver", Wire(reply.Packet))?.Reason);

        var again = Wire(sender.Request("receiver", [photo]));
        Assert.IsType<FlyyDrop.Incoming.Ask>(receiver.OnRequest("sender", again, isPaired: true));
    }

    [Fact]
    public void EveryoneForTenMinutesRunsOut()
    {
        receiver.ReceivingMode = FlyyDrop.Receiving.EveryoneFor10Minutes;
        Assert.Equal(now + FlyyDrop.EveryoneMs, receiver.ReceivingUntil);

        now += FlyyDrop.EveryoneMs;
        Assert.Equal(FlyyDrop.Receiving.Off, receiver.ReceivingMode);
        Assert.Null(receiver.ReceivingUntil);
    }

    [Fact]
    public void OneRequestAtATimePerDevice()
    {
        Ask();
        var second = Wire(sender.Request("receiver", [notes]));

        var reply = Assert.IsType<FlyyDrop.Incoming.Reply>(receiver.OnRequest("sender", second, isPaired: false));
        Assert.Equal(FlyyDrop.Reason.Busy, FlyyDrop.ReasonOf(reply.Packet.GetString("reason")));
    }

    [Fact]
    public void UnansweredRequestsExpire()
    {
        var offer = Ask();

        now += FlyyDrop.AskMs;
        Assert.Equal([offer.Id], receiver.Expire().Select(o => o.Id));
        Assert.Null(receiver.Accept(offer.Id));
    }

    [Fact]
    public void CancelReachesTheOtherSide()
    {
        var offer = Ask();
        var cancel = sender.Cancel(offer.Id)!;

        Assert.True(sender.AdmitsOutgoing("receiver", cancel));
        Assert.Null(receiver.OnCancel("intruder", Wire(cancel)));
        Assert.Equal(offer.Id, receiver.OnCancel("sender", Wire(cancel))?.Id);
        Assert.False(receiver.IsActive(offer.Id));
    }

    [Fact]
    public void ResponsesOnlyCountFromTheAskedDevice()
    {
        var request = sender.Request("receiver", [photo]);
        var forged = new NetworkPacket(PacketType.FlyyDropResponse, new() { ["id"] = request.GetString("id"), ["accept"] = true });

        Assert.False(sender.AdmitsIncoming("intruder", forged));
        Assert.Null(sender.OnResponse("intruder", forged));
        Assert.NotNull(sender.OnResponse("receiver", forged));
    }

    [Fact]
    public void MalformedRequestsAreIgnored()
    {
        Assert.Null(FlyyDrop.OfferOf("d", new NetworkPacket(PacketType.FlyyDropRequest, new() { ["id"] = "x" })));
        Assert.Null(FlyyDrop.OfferOf("d", new NetworkPacket(PacketType.FlyyDropRequest, new() { ["text"] = "hi" })));

        var negative = NetworkPacket.Parse("""{"id":1,"type":"aproid.flyydrop.request","body":{"id":"x","files":[{"name":"a","size":-1}]}}""");
        Assert.Null(FlyyDrop.OfferOf("d", negative));
        Assert.Equal("passwd", new FlyyDrop.Item("../../etc/passwd", 1).SafeName);
    }
}
