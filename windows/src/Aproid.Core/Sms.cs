using System.Text.Json.Nodes;

namespace Aproid.Core;

/// A phone number or email a message went to or came from. `Name` is the phone's contact name, if any.
public sealed record SmsAddress(string Address, string? Name = null);

/// A picture or file in an MMS. `Thumbnail` is a small base64 JPEG.
public sealed record SmsAttachment(long PartId, string MimeType, string UniqueId, string? Thumbnail = null);

/// One text or MMS, in the shape of KDE Connect's "kdeconnect.sms.messages". Mirrors Sms.kt and Sms.swift.
public sealed record SmsMessage(
    long Id,
    long ThreadId,
    string Body,
    IReadOnlyList<SmsAddress> Addresses,
    long Date,
    bool IsIncoming,
    bool IsRead = true,
    long? SubscriptionId = null,
    IReadOnlyList<SmsAttachment>? Attachments = null)
{
    public const long TypeInbox = 1;
    public const long TypeSent = 2;

    public IReadOnlyList<SmsAttachment> Parts => Attachments ?? [];

    public static SmsMessage? FromJson(JsonObject json)
    {
        if (Number(json, "_id") is not long id || Number(json, "thread_id") is not long threadId) return null;

        var addresses = (json["addresses"] as JsonArray ?? [])
            .OfType<JsonObject>()
            .Where(item => item["address"].AsString() is not null)
            .Select(item => new SmsAddress(item["address"].AsString()!, item["name"].AsString()))
            .ToList();
        var attachments = (json["attachments"] as JsonArray ?? [])
            .OfType<JsonObject>()
            .Where(part => Number(part, "part_id") is not null)
            .Select(part => new SmsAttachment(
                Number(part, "part_id")!.Value,
                part["mime_type"].AsString() ?? "",
                part["unique_identifier"].AsString() ?? "",
                part["encoded_thumbnail"].AsString()))
            .ToList();

        return new SmsMessage(
            id,
            threadId,
            json["body"].AsString() ?? "",
            addresses,
            Number(json, "date") ?? 0,
            Number(json, "type") != TypeSent,
            Number(json, "read") is long read ? read != 0 : json["read"].AsBool() ?? true,
            Number(json, "sub_id"),
            attachments);
    }

    public JsonObject ToJson()
    {
        var json = new JsonObject
        {
            ["_id"] = Id,
            ["thread_id"] = ThreadId,
            ["body"] = Body,
            ["date"] = Date,
            ["type"] = IsIncoming ? TypeInbox : TypeSent,
            ["read"] = IsRead ? 1 : 0,
            ["event"] = Addresses.Count > 1 ? 2 : 1,
            ["addresses"] = new JsonArray(Addresses.Select(a =>
            {
                var item = new JsonObject { ["address"] = a.Address };
                if (a.Name is not null) item["name"] = a.Name;
                return (JsonNode)item;
            }).ToArray()),
        };
        if (SubscriptionId is long sub) json["sub_id"] = sub;
        if (Parts.Count > 0)
        {
            json["attachments"] = new JsonArray(Parts.Select(a =>
            {
                var item = new JsonObject { ["part_id"] = a.PartId, ["mime_type"] = a.MimeType, ["unique_identifier"] = a.UniqueId };
                if (a.Thumbnail is not null) item["encoded_thumbnail"] = a.Thumbnail;
                return (JsonNode)item;
            }).ToArray());
        }

        return json;
    }

    /// A number that may arrive as a string, as some KDE Connect versions send ids.
    internal static long? Number(JsonObject json, string key) =>
        json[key].AsLong() ?? (long.TryParse(json[key].AsString(), out var parsed) ? parsed : null);
}

/// The SMS packets: message lists from the phone, and what the computer asks for.
public static class Sms
{
    public sealed record ConversationRequest(long ThreadId, long? Before, long? Count);

    public sealed record SendRequest(IReadOnlyList<string> Addresses, string Body, long? SubscriptionId);

    public static NetworkPacket MessagesPacket(IEnumerable<SmsMessage> messages) =>
        new(PacketType.SmsMessages, new JsonObject { ["version"] = 2, ["messages"] = new JsonArray(messages.Select(m => (JsonNode)m.ToJson()).ToArray()) });

    public static IReadOnlyList<SmsMessage>? Messages(NetworkPacket packet)
    {
        if (packet.Type != PacketType.SmsMessages) return null;

        return (packet.Body["messages"] as JsonArray ?? []).OfType<JsonObject>().Select(SmsMessage.FromJson).OfType<SmsMessage>().ToList();
    }

    /// Asks for the newest message of every conversation.
    public static NetworkPacket RequestConversations() => new(PacketType.SmsRequestConversations);

    /// Asks for up to `count` messages of one conversation, older than `before` when set.
    public static NetworkPacket RequestConversation(long threadId, long? before = null, long count = 50)
    {
        var body = new JsonObject { ["threadID"] = threadId, ["numberToRequest"] = count };
        if (before is long b) body["rangeStartTimestamp"] = b;

        return new NetworkPacket(PacketType.SmsRequestConversation, body);
    }

    public static ConversationRequest? ConversationRequestOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.SmsRequestConversation || packet.GetLong("threadID") is not long threadId) return null;

        var before = packet.GetLong("rangeStartTimestamp") is long b and > 0 ? b : (long?)null;

        return new ConversationRequest(threadId, before, packet.GetLong("numberToRequest"));
    }

    public static NetworkPacket Send(IEnumerable<string> addresses, string body, long? subscriptionId = null)
    {
        var packetBody = new JsonObject
        {
            ["version"] = 2,
            ["messageBody"] = body,
            ["addresses"] = new JsonArray(addresses.Select(a => (JsonNode)new JsonObject { ["address"] = a }).ToArray()),
        };
        if (subscriptionId is long sub) packetBody["subID"] = sub;

        return new NetworkPacket(PacketType.SmsRequest, packetBody);
    }

    public static SendRequest? SendRequestOf(NetworkPacket packet)
    {
        if (packet.Type != PacketType.SmsRequest || packet.GetString("messageBody") is not string body) return null;

        // Version 1 sent a single "phoneNumber".
        var addresses = packet.Body["addresses"] is JsonArray list
            ? list.OfType<JsonObject>().Select(item => item["address"].AsString()).OfType<string>().ToList()
            : new[] { packet.GetString("phoneNumber") }.OfType<string>().ToList();
        if (addresses.Count == 0) return null;

        return new SendRequest(addresses, body, packet.GetLong("subID"));
    }
}
