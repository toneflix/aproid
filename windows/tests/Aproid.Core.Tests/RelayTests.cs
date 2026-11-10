using Aproid.Core;

namespace Aproid.Core.Tests;

/// Mirrors RelayTests.swift and RelayTest.kt.
public class RelayTests
{
    private static NetworkPacket Wire(NetworkPacket packet) => NetworkPacket.Parse(packet.Serialize());

    [Fact]
    public void PhonePacketsRoundTrip()
    {
        var call = Call.Event(CallEvent.Ringing, "+2348000000000", "Ada");
        var message = Relay.MessageOf(Wire(Relay.Wrap(call, "phone1", "Pixel")))!;

        Assert.Equal("phone1", message.PhoneId);
        Assert.Equal("Pixel", message.PhoneName);
        Assert.Equal(PacketType.Telephony, message.Packet.Type);
        Assert.Equal(Call.StateOf(call), Call.StateOf(message.Packet));
    }

    [Fact]
    public void AnswersRoundTrip()
    {
        var reply = NotificationRequests.Reply("r1", "On my way");
        var message = Relay.MessageOf(Wire(Relay.Wrap(reply, "phone1", "Pixel")))!;

        Assert.Equal(reply.Type, message.Packet.Type);
        Assert.Equal(reply.Body.ToJsonString(), message.Packet.Body.ToJsonString());
    }

    [Fact]
    public void OnlyRelayablePacketsAreAccepted()
    {
        Assert.Null(Relay.MessageOf(Wire(Relay.Wrap(new NetworkPacket(PacketType.Ping), "phone1", "Pixel"))));
        Assert.Null(Relay.MessageOf(Wire(Relay.Wrap(Call.Event(CallEvent.Missed, "1"), "", "Pixel"))));
        Assert.Null(Relay.MessageOf(new NetworkPacket(PacketType.Relay, new System.Text.Json.Nodes.JsonObject { ["phoneId"] = "phone1" })));
        Assert.Equal("Phone", Relay.MessageOf(Wire(Relay.Wrap(Call.Event(CallEvent.Missed, "1"), "p", "")))?.PhoneName);
    }
}
