using FlyyLink.Core;
using FlyyLink.Model;

namespace FlyyLink.Plugins;

/// FlyyDrop on the PC: asks nearby devices, paired or not, to take files or a link, and asks the user before taking
/// theirs. `Drop` is the one authority on what an unpaired device may send or receive; accepted files then move
/// through `SharePlugin` like any other share.
internal sealed class FlyyDropPlugin(SharePlugin share, DeviceRegistry devices) : IPlugin
{
    private sealed record Pending(IReadOnlyList<string> Paths, string? Text);

    private readonly object gate = new();
    private readonly Dictionary<string, Pending> pending = [];

    /// The device each request waiting for the user came from.
    private readonly Dictionary<string, string> asking = [];

    public FlyyDrop Drop { get; } = new();

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.FlyyDropRequest, PacketType.FlyyDropResponse, PacketType.FlyyDropCancel };

    /// Someone asked to send something. Called on any thread.
    public Action<FlyyDropAsk>? OnAsk { get; set; }

    /// A request was answered, cancelled or ran out, so its prompt can go.
    public Action<string>? OnAskEnded { get; set; }

    /// One of our FlyyDrops moved on, keyed by the device it goes to.
    public Action<string, FlyyDropSend>? OnSend { get; set; }

    /// Shows a sent link or text in Recent.
    public Action<Activity>? OnActivity { get; set; }

    // Sending

    /// Asks `device` to take the files at `paths` and/or `text`.
    public void Send(IReadOnlyList<string> paths, string? text, Device device)
    {
        var files = paths.Select(path => new FileInfo(path)).Where(info => info.Exists).ToList();
        var items = files.Select(info => new FlyyDrop.Item(info.Name, info.Length)).ToList();
        if (items.Count == 0 && string.IsNullOrEmpty(text)) return;

        var packet = Drop.Request(device.Id, items, text);
        if (packet.GetString("id") is not string id) return;

        lock (gate) pending[id] = new Pending(files.Select(info => info.FullName).ToList(), text);
        OnSend?.Invoke(device.Id, new FlyyDropSend(id, FlyyDropStage.Waiting));
        device.Send(packet);
    }

    /// Stops waiting for an answer to `id`.
    public void Cancel(string id, string deviceId)
    {
        lock (gate) pending.Remove(id);

        if (Drop.Cancel(id) is NetworkPacket packet) devices[deviceId]?.Send(packet);
    }

    private void Answered(FlyyDrop.Answer answer, Device device)
    {
        var id = answer.Offer.Id;
        Pending? sent;
        lock (gate)
        {
            if (!pending.Remove(id, out sent)) return;
        }

        if (!answer.Accepted)
        {
            OnSend?.Invoke(device.Id, new FlyyDropSend(id, FlyyDropStage.Declined, Reason: answer.Reason));
            return;
        }

        if (sent.Text is string text)
        {
            device.Send(FlyyDrop.Text(id, text));
            OnActivity?.Invoke(new Activity(ActivityKind.Text, $"“{(text.Length > 60 ? text[..60] : text)}”", $"FlyyDropped to {device.Name}"));
        }

        if (sent.Paths.Count == 0)
        {
            OnSend?.Invoke(device.Id, new FlyyDropSend(id, FlyyDropStage.Sent));
            return;
        }

        SendFiles(sent.Paths, id, answer.Offer.TotalSize, device);
    }

    /// Offers every accepted file at once and reports progress across all of them.
    private void SendFiles(IReadOnlyList<string> paths, string id, long total, Device device)
    {
        var progress = new TransferProgress(total);
        var left = paths.Count;
        var failed = false;
        var deviceId = device.Id;

        OnSend?.Invoke(deviceId, new FlyyDropSend(id, FlyyDropStage.Sending, progress.Read()));

        foreach (var path in paths)
        {
            share.Send(path, device, id, bytes =>
            {
                if (progress.Advance(bytes) is { } reading) OnSend?.Invoke(deviceId, new FlyyDropSend(id, FlyyDropStage.Sending, reading));
            }, error =>
            {
                bool done;
                lock (gate)
                {
                    failed |= error is not null;
                    done = --left == 0;
                }

                if (done) OnSend?.Invoke(deviceId, new FlyyDropSend(id, failed ? FlyyDropStage.Failed : FlyyDropStage.Sent));
            });
        }
    }

    // Receiving

    public void Accept(string id) => Answer(id, Drop.Accept(id));

    public void Decline(string id) => Answer(id, Drop.Decline(id));

    private void Answer(string id, NetworkPacket? packet)
    {
        string? deviceId;
        lock (gate)
        {
            if (!asking.Remove(id, out deviceId)) return;
        }

        OnAskEnded?.Invoke(id);
        if (packet is not null) devices[deviceId]?.Send(packet);
    }

    private void Requested(NetworkPacket packet, Device device)
    {
        switch (Drop.OnRequest(device.Id, packet, device.IsPaired))
        {
            case FlyyDrop.Incoming.Ask ask:
                lock (gate) asking[ask.Offer.Id] = device.Id;
                OnAsk?.Invoke(new FlyyDropAsk(ask.Offer, device.Name, device.Link.Identity.DeviceType, device.IsPaired));
                break;
            case FlyyDrop.Incoming.Reply reply:
                device.Send(reply.Packet);
                break;
        }
    }

    public void OnPacket(NetworkPacket packet, Device device)
    {
        switch (packet.Type)
        {
            case PacketType.FlyyDropRequest:
                Requested(packet, device);
                break;
            case PacketType.FlyyDropResponse:
                if (Drop.OnResponse(device.Id, packet) is FlyyDrop.Answer answer) Answered(answer, device);
                break;
            case PacketType.FlyyDropCancel:
                if (Drop.OnCancel(device.Id, packet) is FlyyDrop.Offer offer) Ended(offer);
                break;
        }
    }

    /// Call every few seconds: drops requests nobody answered.
    public void Tick()
    {
        foreach (var offer in Drop.Expire()) Ended(offer);
    }

    private void Ended(FlyyDrop.Offer offer)
    {
        bool wasAsking, wasPending;
        lock (gate)
        {
            wasAsking = asking.Remove(offer.Id);
            wasPending = pending.Remove(offer.Id);
        }

        if (wasAsking) OnAskEnded?.Invoke(offer.Id);
        if (wasPending) OnSend?.Invoke(offer.DeviceId, new FlyyDropSend(offer.Id, FlyyDropStage.NoAnswer));
    }
}
