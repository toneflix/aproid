using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Aproid.Core;

/// Lets some packets pass to and from a device that is not paired. `Device` asks before delivering or sending one.
public interface IGuestAccess
{
    /// True when `packet` from the unpaired `deviceId` may reach the plugins.
    bool AdmitsIncoming(string deviceId, NetworkPacket packet);

    /// True when `packet` may go to the unpaired `deviceId`.
    bool AdmitsOutgoing(string deviceId, NetworkPacket packet);
}

/// FlyyDrop: AirDrop-style sharing with any nearby Aproid device, paired or not.
///
/// The sender asks first with "aproid.flyydrop.request", listing the files or the link or text. The receiver's user
/// accepts or declines ("aproid.flyydrop.response"), and only then do the items arrive as ordinary
/// "kdeconnect.share.request" packets tagged with the request's id. An unpaired device gets nothing more: as its
/// `IGuestAccess`, this class lets in exactly the accepted items, once each. Mirrors FlyyDrop.kt and FlyyDrop.swift.
public sealed partial class FlyyDrop(Func<long>? clock = null) : IGuestAccess
{
    /// Who may send this device a request without being paired.
    public enum Receiving { Off, EveryoneFor10Minutes, Everyone }

    /// Why a request was turned down.
    public enum Reason { Declined, Unavailable, Busy }

    public sealed record Item(string Name, long Size)
    {
        public string SafeName => Share.SafeName(Name);
    }

    /// One request: files, or a link or some text, between this device and `DeviceId`.
    public sealed record Offer(string Id, string DeviceId, IReadOnlyList<Item> Items, string? Text = null)
    {
        public long TotalSize => Items.Sum(item => item.Size);
    }

    /// What to do with a request that arrived: ask the user, or send `Packet` straight back.
    public abstract record Incoming
    {
        public sealed record Ask(Offer Offer) : Incoming;

        public sealed record Reply(NetworkPacket Packet) : Incoming;
    }

    /// The receiver's answer to one of our requests.
    public sealed record Answer(Offer Offer, bool Accepted, Reason? Reason);

    /// How long a request waits for the user to answer, in milliseconds.
    public const long AskMs = 60_000;

    /// How long an accepted request waits for its next item.
    public const long AcceptedMs = 60 * 60_000;

    /// How long "Everyone for 10 minutes" lasts.
    public const long EveryoneMs = 10 * 60_000;

    /// Requests waiting for an answer at once, from all devices.
    public const int MaxAsking = 3;

    public const int MaxItems = 1000;
    public const int MaxText = 64 * 1024;

    /// The share packet field that says which request an item belongs to.
    public const string Tag = "aproid.flyydrop";

    /// The sender waits a little longer than the receiver, so the receiver's answer always wins.
    private const long GraceMs = 5_000;

    private enum Stage { Asking, Accepted }

    private sealed class Transfer(Offer offer, Stage stage, long expires)
    {
        public Offer Offer { get; } = offer;
        public Stage Stage { get; set; } = stage;
        public long Expires { get; set; } = expires;
        public List<Item> Waiting { get; } = [.. offer.Items];
        public bool TextWaiting { get; set; } = offer.Text is not null;

        public bool IsDone => Waiting.Count == 0 && !TextWaiting;

        public bool Matches(string deviceId, Stage stage) => Offer.DeviceId == deviceId && Stage == stage;
    }

    private readonly Func<long> clock = clock ?? (() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
    private readonly object gate = new();
    private readonly Dictionary<string, Transfer> incoming = [];
    private readonly Dictionary<string, Transfer> outgoing = [];
    private Receiving mode = Receiving.Off;
    private long everyoneUntil;

    /// Who may send a request now. "Everyone for 10 minutes" reads as off once the time is up.
    public Receiving ReceivingMode
    {
        get
        {
            lock (gate) return CurrentReceiving;
        }
        set
        {
            lock (gate)
            {
                mode = value;
                everyoneUntil = clock() + EveryoneMs;
            }
        }
    }

    /// When "Everyone for 10 minutes" ends, in milliseconds, or null for the other settings.
    public long? ReceivingUntil
    {
        get
        {
            lock (gate) return CurrentReceiving == Receiving.EveryoneFor10Minutes ? everyoneUntil : null;
        }
    }

    /// Puts back a setting saved earlier, keeping its original end time.
    public void Restore(Receiving receiving, long? until)
    {
        lock (gate)
        {
            mode = receiving;
            everyoneUntil = until ?? 0;
        }
    }

    private Receiving CurrentReceiving => mode == Receiving.EveryoneFor10Minutes && clock() >= everyoneUntil ? Receiving.Off : mode;

    // Sending

    /// Starts a request to `deviceId`. Send the returned packet, then wait for `OnResponse`.
    public NetworkPacket Request(string deviceId, IReadOnlyList<Item> items, string? text = null)
    {
        text = string.IsNullOrEmpty(text) ? null : text;
        if (items.Count == 0 && text is null) throw new ArgumentException("nothing to send");

        var offer = new Offer(Guid.NewGuid().ToString(), deviceId, items, text);
        lock (gate) outgoing[offer.Id] = new Transfer(offer, Stage.Asking, clock() + AskMs + GraceMs);

        return RequestPacket(offer);
    }

    /// Reads the receiver's answer to one of our requests.
    public Answer? OnResponse(string deviceId, NetworkPacket packet)
    {
        if (packet.Type != PacketType.FlyyDropResponse || packet.GetString("id") is not string id) return null;

        lock (gate)
        {
            if (!outgoing.TryGetValue(id, out var transfer) || !transfer.Matches(deviceId, Stage.Asking)) return null;

            var accepted = packet.GetBool("accept") == true;
            if (accepted)
            {
                transfer.Stage = Stage.Accepted;
                transfer.Expires = clock() + AcceptedMs;
            }
            else
            {
                outgoing.Remove(id);
            }

            return new Answer(transfer.Offer, accepted, accepted ? null : ReasonOf(packet.GetString("reason")));
        }
    }

    // Receiving

    /// Decides what to do with a request from `deviceId`. Returns null for a malformed or repeated one.
    public Incoming? OnRequest(string deviceId, NetworkPacket packet, bool isPaired)
    {
        if (OfferOf(deviceId, packet) is not Offer offer) return null;

        lock (gate)
        {
            if (incoming.ContainsKey(offer.Id)) return null;

            if (!isPaired && CurrentReceiving == Receiving.Off) return new Incoming.Reply(Response(offer.Id, Reason.Unavailable));

            var asking = incoming.Values.Where(t => t.Stage == Stage.Asking).ToList();
            if (asking.Count >= MaxAsking || asking.Any(t => t.Offer.DeviceId == deviceId)) return new Incoming.Reply(Response(offer.Id, Reason.Busy));

            incoming[offer.Id] = new Transfer(offer, Stage.Asking, clock() + AskMs);

            return new Incoming.Ask(offer);
        }
    }

    /// The user accepted. Send the returned packet; the items may then come in.
    public NetworkPacket? Accept(string id)
    {
        lock (gate)
        {
            if (!incoming.TryGetValue(id, out var transfer) || transfer.Stage != Stage.Asking) return null;

            transfer.Stage = Stage.Accepted;
            transfer.Expires = clock() + AcceptedMs;

            return new NetworkPacket(PacketType.FlyyDropResponse, new JsonObject { ["id"] = id, ["accept"] = true });
        }
    }

    /// The user declined. Send the returned packet.
    public NetworkPacket? Decline(string id)
    {
        lock (gate)
        {
            return incoming.Remove(id) ? Response(id, Reason.Declined) : null;
        }
    }

    // Either side

    /// Stops a request in either direction. Send the returned packet to tell the other device.
    public NetworkPacket? Cancel(string id)
    {
        lock (gate)
        {
            if (!incoming.Remove(id) && !outgoing.Remove(id)) return null;

            return new NetworkPacket(PacketType.FlyyDropCancel, new JsonObject { ["id"] = id });
        }
    }

    /// The other device stopped a request. Returns it, so its prompt or progress can go away.
    public Offer? OnCancel(string deviceId, NetworkPacket packet)
    {
        if (packet.Type != PacketType.FlyyDropCancel || packet.GetString("id") is not string id) return null;

        lock (gate)
        {
            foreach (var transfers in new[] { incoming, outgoing })
            {
                if (transfers.TryGetValue(id, out var transfer) && transfer.Offer.DeviceId == deviceId)
                {
                    transfers.Remove(id);
                    return transfer.Offer;
                }
            }

            return null;
        }
    }

    /// Forgets requests nobody answered and accepted ones that went quiet, and returns them. Call every few seconds.
    public IReadOnlyList<Offer> Expire()
    {
        lock (gate)
        {
            var now = clock();
            var expired = new List<Offer>();

            foreach (var transfers in new[] { incoming, outgoing })
            {
                foreach (var (id, transfer) in transfers.Where(pair => pair.Value.Expires <= now).ToList())
                {
                    transfers.Remove(id);
                    expired.Add(transfer.Offer);
                }
            }

            return expired;
        }
    }

    /// True while `id` is waiting for an answer or still has items to move.
    public bool IsActive(string id)
    {
        lock (gate) return incoming.ContainsKey(id) || outgoing.ContainsKey(id);
    }

    // IGuestAccess

    public bool AdmitsIncoming(string deviceId, NetworkPacket packet)
    {
        lock (gate)
        {
            return packet.Type switch
            {
                PacketType.FlyyDropRequest or PacketType.FlyyDropCancel => true,
                PacketType.FlyyDropResponse => packet.GetString("id") is string id && outgoing.TryGetValue(id, out var t) && t.Matches(deviceId, Stage.Asking),
                PacketType.ShareRequest => Take(incoming, deviceId, packet, packet.PayloadSize),
                _ => false,
            };
        }
    }

    public bool AdmitsOutgoing(string deviceId, NetworkPacket packet)
    {
        lock (gate)
        {
            return packet.Type switch
            {
                PacketType.FlyyDropRequest => packet.GetString("id") is string id && outgoing.TryGetValue(id, out var t) && t.Matches(deviceId, Stage.Asking),
                PacketType.FlyyDropCancel => true,
                PacketType.FlyyDropResponse => packet.GetBool("accept") != true
                    || (packet.GetString("id") is string id && incoming.TryGetValue(id, out var t) && t.Matches(deviceId, Stage.Accepted)),
                PacketType.ShareRequest => Take(outgoing, deviceId, packet, packet.GetLong("totalPayloadSize")),
                _ => false,
            };
        }
    }

    /// Lets one accepted item through, once, and forgets the request after its last item.
    private bool Take(Dictionary<string, Transfer> transfers, string deviceId, NetworkPacket packet, long? size)
    {
        if (packet.GetString(Tag) is not string id || !transfers.TryGetValue(id, out var transfer) || !transfer.Matches(deviceId, Stage.Accepted)) return false;

        if (packet.GetString("filename") is string name)
        {
            if ((packet.GetLong("aproid.offset") ?? 0) != 0 || !transfer.Waiting.Remove(new Item(name, size ?? -1))) return false;
        }
        else if ((packet.GetString("url") ?? packet.GetString("text")) is string text && transfer.TextWaiting && text == transfer.Offer.Text)
        {
            transfer.TextWaiting = false;
        }
        else
        {
            return false;
        }

        if (transfer.IsDone) transfers.Remove(id);
        else transfer.Expires = clock() + AcceptedMs;

        return true;
    }

    // Packets

    /// A file of an accepted request. Send it with `Device.SendWithPayload`.
    public static NetworkPacket File(string id, Item item) => Tagged(Share.FilePacket(item.Name, item.Size), id);

    /// The link or text of an accepted request.
    public static NetworkPacket Text(string id, string text) => Tagged(LinkPattern().IsMatch(text) ? Share.LinkPacket(text) : Share.TextPacket(text), id);

    /// The request an item belongs to, or null for an ordinary share.
    public static string? RequestId(NetworkPacket packet) => packet.GetString(Tag);

    public static NetworkPacket RequestPacket(Offer offer)
    {
        var files = new JsonArray();
        foreach (var item in offer.Items) files.Add(new JsonObject { ["name"] = item.Name, ["size"] = item.Size });

        var body = new JsonObject { ["id"] = offer.Id, ["files"] = files };
        if (offer.Text is not null) body["text"] = offer.Text;

        return new NetworkPacket(PacketType.FlyyDropRequest, body);
    }

    /// Reads a request, or null when it is malformed or too big.
    public static Offer? OfferOf(string deviceId, NetworkPacket packet)
    {
        if (packet.Type != PacketType.FlyyDropRequest || packet.GetString("id") is not { Length: > 0 and <= 64 } id) return null;

        var files = packet.Body["files"] as JsonArray ?? [];
        if (files.Count > MaxItems) return null;

        var items = new List<Item>();
        foreach (var file in files)
        {
            if (file is not JsonObject json) return null;
            if (json["name"].AsString() is not string name || string.IsNullOrWhiteSpace(name)) return null;
            if (json["size"].AsLong() is not (long size and >= 0)) return null;

            items.Add(new Item(name, size));
        }

        var text = packet.GetString("text") is { Length: > 0 } given ? given : null;
        if (text is { Length: > MaxText }) return null;
        if (items.Count == 0 && text is null) return null;

        return new Offer(id, deviceId, items, text);
    }

    public static string WireName(Reason reason) => reason switch
    {
        Reason.Unavailable => "unavailable",
        Reason.Busy => "busy",
        _ => "declined",
    };

    public static Reason ReasonOf(string? wire) => wire switch
    {
        "unavailable" => Reason.Unavailable,
        "busy" => Reason.Busy,
        _ => Reason.Declined,
    };

    private static NetworkPacket Response(string id, Reason reason) =>
        new(PacketType.FlyyDropResponse, new JsonObject { ["id"] = id, ["accept"] = false, ["reason"] = WireName(reason) });

    private static NetworkPacket Tagged(NetworkPacket packet, string id)
    {
        packet.Body[Tag] = id;

        return packet;
    }

    [GeneratedRegex(@"^https?://\S+$", RegexOptions.IgnoreCase)]
    private static partial Regex LinkPattern();
}
