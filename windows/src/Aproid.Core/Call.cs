using System.Text.Json.Nodes;

namespace Aproid.Core;

/// What a "kdeconnect.telephony" packet reports about a call. Mirrors Call.kt and Call.swift.
public enum CallEvent
{
    Ringing,
    Talking,
    Missed,
}

/// Calls: the phone reports them with "kdeconnect.telephony", and the computer controls them with "aproid.call.request".
public static class Call
{
    public enum Action
    {
        Answer,
        Decline,
        HangUp,
        Mute,
        Unmute,
        Dial,
    }

    public sealed record Request(Action Action, string? Number = null);

    /// `Photo` is the caller's contact photo as base64 JPEG. `Ended` means the call is over.
    public sealed record State(CallEvent Event, string Number, string? ContactName = null, string? Photo = null, bool Ended = false);

    public static string WireName(this CallEvent callEvent) => callEvent switch
    {
        CallEvent.Ringing => "ringing",
        CallEvent.Talking => "talking",
        _ => "missedCall",
    };

    public static string WireName(this Action action) => action switch
    {
        Action.HangUp => "hangUp",
        _ => action.ToString().ToLowerInvariant(),
    };

    public static NetworkPacket Event(CallEvent callEvent, string number, string? contactName = null, string? photo = null)
    {
        var body = new JsonObject { ["event"] = callEvent.WireName(), ["phoneNumber"] = number };
        if (contactName is not null) body["contactName"] = contactName;
        if (photo is not null) body["phoneThumbnail"] = photo;

        return new NetworkPacket(PacketType.Telephony, body);
    }

    public static NetworkPacket Ended(string number) =>
        new(PacketType.Telephony, new JsonObject { ["event"] = CallEvent.Ringing.WireName(), ["phoneNumber"] = number, ["isCancel"] = true });

    public static State? StateOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Telephony) return null;

        CallEvent? callEvent = packet.GetString("event") switch
        {
            "ringing" => CallEvent.Ringing,
            "talking" => CallEvent.Talking,
            "missedCall" => CallEvent.Missed,
            _ => null,
        };
        if (callEvent is not CallEvent known) return null;

        return new State(
            known,
            packet.GetString("phoneNumber") ?? "",
            packet.GetString("contactName") is { Length: > 0 } name ? name : null,
            packet.GetString("phoneThumbnail") is { Length: > 0 } photo ? photo : null,
            packet.GetBool("isCancel") == true);
    }

    public static NetworkPacket Answer() => Packet(new Request(Action.Answer));

    public static NetworkPacket Decline() => Packet(new Request(Action.Decline));

    public static NetworkPacket HangUp() => Packet(new Request(Action.HangUp));

    public static NetworkPacket Mute(bool muted) => Packet(new Request(muted ? Action.Mute : Action.Unmute));

    public static NetworkPacket Dial(string number) => Packet(new Request(Action.Dial, number));

    public static NetworkPacket Packet(Request request)
    {
        var body = new JsonObject { ["action"] = request.Action.WireName() };
        if (request.Number is not null) body["number"] = request.Number;

        return new NetworkPacket(PacketType.CallRequest, body);
    }

    public static Request? RequestOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.CallRequest) return null;

        var action = Enum.GetValues<Action>().Cast<Action?>().FirstOrDefault(a => a!.Value.WireName() == packet.GetString("action"));
        if (action is not Action known) return null;

        var number = packet.GetString("number") is { } n && n.Trim().Length > 0 ? n : null;
        if (known == Action.Dial && number is null) return null;

        return new Request(known, number);
    }
}
