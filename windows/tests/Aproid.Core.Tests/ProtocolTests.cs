using System.Text.Json.Nodes;
using Aproid.Core;

namespace Aproid.Core.Tests;

public class NetworkPacketTests
{
    [Fact]
    public void SerializeEndsWithNewlineAndRoundTrips()
    {
        var packet = new NetworkPacket(PacketType.Ping, new JsonObject { ["message"] = "hi" }, id: 42);

        var data = packet.Serialize();
        var back = NetworkPacket.Parse(data);

        Assert.Equal((byte)'\n', data[^1]);
        Assert.Single(data, b => b == (byte)'\n');
        Assert.Equal(42, back.Id);
        Assert.Equal(PacketType.Ping, back.Type);
        Assert.Equal("hi", back.GetString("message"));
    }

    [Fact]
    public void WritesSortedKeysWithoutEscapingSlashes()
    {
        var packet = new NetworkPacket(PacketType.ShareRequest, new JsonObject { ["url"] = "https://kde.org/é", ["a"] = 1 }, id: 1);

        var line = packet.ToString();

        Assert.Equal("""{"body":{"a":1,"url":"https://kde.org/é"},"id":1,"type":"kdeconnect.share.request"}""", line);
    }

    [Fact]
    public void ParsesStringId()
    {
        Assert.Equal(123, NetworkPacket.Parse("""{"id":"123","type":"kdeconnect.ping","body":{}}""").Id);
    }

    [Fact]
    public void PayloadFields()
    {
        var packet = new NetworkPacket(PacketType.ShareRequest, new JsonObject { ["filename"] = "a.jpg" }, id: 1, payloadSize: 2048, payloadTransferInfo: new JsonObject { ["port"] = 1739 });

        var back = NetworkPacket.Parse(packet.Serialize());

        Assert.Equal(2048, back.PayloadSize);
        Assert.Equal(1739, back.PayloadPort);
    }

    [Fact]
    public void RejectsMissingType()
    {
        Assert.Throws<ProtocolException>(() => NetworkPacket.Parse("""{"id":1,"body":{}}"""));
        Assert.Throws<ProtocolException>(() => NetworkPacket.Parse("not json"));
    }

    [Fact]
    public void ReadsKotlinStylePacket()
    {
        const string wire = """{"id":1700000000000,"type":"kdeconnect.identity","body":{"deviceId":"_0123456789abcdef0123456789abcdef_","deviceName":"Pixel","deviceType":"phone","protocolVersion":8,"incomingCapabilities":["kdeconnect.ping"],"outgoingCapabilities":[],"tcpPort":1716}}""";

        var identity = DeviceIdentity.FromPacket(NetworkPacket.Parse(wire));

        Assert.Equal(DeviceType.Phone, identity.DeviceType);
        Assert.Equal(1716, identity.TcpPort);
        Assert.Equal(["kdeconnect.ping"], identity.IncomingCapabilities);
    }

    [Fact]
    public void ReadsWholeNumbersSentAsDoubles()
    {
        var packet = NetworkPacket.Parse("""{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":50.0}}""");

        Assert.Equal(50, packet.GetLong("currentCharge"));
    }
}

public class DeviceIdentityTests
{
    [Fact]
    public void NewIdsAreValid()
    {
        for (var i = 0; i < 20; i++) Assert.True(DeviceIdentity.IsValidDeviceId(DeviceIdentity.NewDeviceId()));
        Assert.False(DeviceIdentity.IsValidDeviceId("short"));
    }

    [Fact]
    public void SanitizesNames()
    {
        Assert.Equal("Obis Laptop", DeviceIdentity.SanitizeName("Obi's Laptop!"));
        Assert.Equal("PC", DeviceIdentity.SanitizeName("..."));
        Assert.Equal(32, DeviceIdentity.SanitizeName(new string('x', 50)).Length);
    }

    [Fact]
    public void RoundTrip()
    {
        var identity = new DeviceIdentity { DeviceId = DeviceIdentity.NewDeviceId(), DeviceName = "PC", DeviceType = DeviceType.Laptop, TcpPort = 1716 };

        var back = DeviceIdentity.FromPacket(NetworkPacket.Parse(identity.ToPacket().Serialize()));

        Assert.Equal(identity, back);
    }
}

public class PairingTests
{
    private static NetworkPacket Pair(bool value, long? timestamp = null)
    {
        var body = new JsonObject { ["pair"] = value };
        if (timestamp is long ts) body["timestamp"] = ts;

        return new NetworkPacket(PacketType.Pair, body);
    }

    [Fact]
    public void WeRequestAndPeerAccepts()
    {
        var machine = new PairingStateMachine();

        var request = machine.RequestPair(1000);

        Assert.Equal(PairActionKind.Send, request.Kind);
        Assert.Equal(1000, request.Packet!.GetLong("timestamp"));
        Assert.Equal(PairAction.Paired, machine.Handle(Pair(true), 1005));
        Assert.Equal(PairState.Paired, machine.State);
    }

    [Fact]
    public void PeerRequestsAndUserAccepts()
    {
        var machine = new PairingStateMachine();

        Assert.Equal(PairAction.AskUser, machine.Handle(Pair(true, 1000), 1001));

        var accept = machine.Accept();
        Assert.True(accept.Packet!.GetBool("pair"));
        Assert.Equal(PairState.Paired, machine.State);
    }

    [Fact]
    public void StaleTimestampIsRefused()
    {
        var machine = new PairingStateMachine();

        var answer = machine.Handle(Pair(true, 0), 100_000);

        Assert.False(answer.Packet!.GetBool("pair"));
        Assert.Equal(PairState.NotPaired, machine.State);
    }

    [Fact]
    public void RequestTimesOut()
    {
        var machine = new PairingStateMachine();
        machine.RequestPair(0);

        Assert.Equal(PairAction.None, machine.Tick(10));
        Assert.Equal(PairAction.Unpaired, machine.Tick(31));
    }
}
