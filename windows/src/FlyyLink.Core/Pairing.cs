using System.Text.Json.Nodes;

namespace FlyyLink.Core;

public enum PairState
{
    NotPaired,
    Requested,
    RequestedByPeer,
    Paired,
}

public enum PairActionKind
{
    None,
    Send,

    /// Ask the user to accept or reject the peer's request.
    AskUser,
    Paired,
    Unpaired,
}

/// What the caller should do after the state machine handles an event.
public sealed record PairAction(PairActionKind Kind, NetworkPacket? Packet = null)
{
    public static readonly PairAction None = new(PairActionKind.None);
    public static readonly PairAction AskUser = new(PairActionKind.AskUser);
    public static readonly PairAction Paired = new(PairActionKind.Paired);
    public static readonly PairAction Unpaired = new(PairActionKind.Unpaired);

    public static PairAction Send(NetworkPacket packet) => new(PairActionKind.Send, packet);
}

/// Pairing for one peer, following KDE Connect protocol v8. Mirrors PairingStateMachine in Kotlin and Swift.
/// Time is passed in for testing. With `allowed` false, this side never asks to pair and refuses every request.
public sealed class PairingStateMachine(
    PairState state = PairState.NotPaired,
    long timeoutSeconds = 30,
    long maxClockSkewSeconds = 1800,
    bool allowed = true)
{
    private long requestedAt;

    public PairState State { get; private set; } = allowed ? state : PairState.NotPaired;

    /// Unix time in seconds of the last pair request. Both sides use it for the verification code.
    public long RequestTimestamp { get; private set; }

    public PairAction RequestPair(long now)
    {
        if (!allowed) return PairAction.None;

        switch (State)
        {
            case PairState.Paired:
            case PairState.Requested:
                return PairAction.None;
            case PairState.RequestedByPeer:
                return Accept();
            default:
                State = PairState.Requested;
                requestedAt = now;
                RequestTimestamp = now;

                return PairAction.Send(PairPacket(true, now));
        }
    }

    public PairAction Accept()
    {
        if (State != PairState.RequestedByPeer) return PairAction.None;

        State = PairState.Paired;

        return PairAction.Send(PairPacket(true, null));
    }

    public PairAction Reject()
    {
        if (State != PairState.RequestedByPeer) return PairAction.None;

        State = PairState.NotPaired;

        return PairAction.Send(PairPacket(false, null));
    }

    public PairAction Unpair()
    {
        if (State == PairState.NotPaired) return PairAction.None;

        State = PairState.NotPaired;

        return PairAction.Send(PairPacket(false, null));
    }

    /// Call regularly. Drops a request that nobody answered.
    public PairAction Tick(long now)
    {
        if (State != PairState.Requested || now - requestedAt <= timeoutSeconds) return PairAction.None;

        State = PairState.NotPaired;

        return PairAction.Unpaired;
    }

    public PairAction Handle(NetworkPacket packet, long now)
    {
        if (packet.Type != PacketType.Pair || packet.GetBool("pair") is not bool wantsPair) return PairAction.None;

        if (!wantsPair)
        {
            var was = State;
            State = PairState.NotPaired;

            return was == PairState.NotPaired ? PairAction.None : PairAction.Unpaired;
        }

        switch (State)
        {
            case PairState.Requested:
                State = PairState.Paired;
                return PairAction.Paired;
            case PairState.NotPaired:
                // Not allowed, or a missing or stale timestamp: refuse, as protocol v8 requires.
                if (!allowed || packet.GetLong("timestamp") is not long ts || Math.Abs(now - ts) > maxClockSkewSeconds)
                    return PairAction.Send(PairPacket(false, null));

                State = PairState.RequestedByPeer;
                RequestTimestamp = ts;
                return PairAction.AskUser;
            case PairState.Paired:
                return PairAction.Send(PairPacket(true, null));
            default:
                return PairAction.None;
        }
    }

    private static NetworkPacket PairPacket(bool pair, long? timestamp)
    {
        var body = new JsonObject { ["pair"] = pair };
        if (timestamp is long ts) body["timestamp"] = ts;

        return new NetworkPacket(PacketType.Pair, body);
    }
}
