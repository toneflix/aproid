using System.Threading.Channels;

namespace Aproid.Core;

/// An encrypted connection to one peer. Callbacks run on a background thread. Mirrors DeviceLink.kt and DeviceLink.swift.
public sealed class DeviceLink
{
    /// Links opened this close together are two sides connecting at the same moment.
    public static readonly TimeSpan RaceWindow = TimeSpan.FromSeconds(3);

    private readonly Stream stream;
    private readonly IDisposable connection;
    private readonly LineReader reader;
    private readonly Channel<byte[]> outbox = Channel.CreateUnbounded<byte[]>(new UnboundedChannelOptions { SingleReader = true });
    private readonly CancellationTokenSource stop = new();
    private readonly object gate = new();
    private string? reason;
    private int closed;

    public DeviceIdentity Identity { get; }

    public byte[] CertificateDer { get; }

    public byte[] PublicKeyDer { get; }

    public string Host { get; }

    /// True when we opened the TCP connection.
    public bool IsOutgoing { get; }

    public DateTimeOffset OpenedAt { get; } = DateTimeOffset.UtcNow;

    public Action<NetworkPacket>? OnPacket { get; set; }

    public Action? OnClosed { get; set; }

    internal DeviceLink(
        DeviceIdentity identity,
        byte[] certificateDer,
        byte[] publicKeyDer,
        string host,
        bool isOutgoing,
        Stream stream,
        IDisposable connection,
        LineReader reader)
    {
        Identity = identity;
        CertificateDer = certificateDer;
        PublicKeyDer = publicKeyDer;
        Host = host;
        IsOutgoing = isOutgoing;
        this.stream = stream;
        this.connection = connection;
        this.reader = reader;
    }

    /// Why the link closed, for logs.
    public string? CloseReason
    {
        get
        {
            lock (gate) return reason;
        }
    }

    public bool IsOpen => Volatile.Read(ref closed) == 0;

    /// Who opened the TCP connection: us or the peer.
    public string OpenerId(string ownDeviceId) => IsOutgoing ? ownDeviceId : Identity.DeviceId;

    /// Decides which link to keep when a second one to the same device arrives.
    /// If both sides connected at the same moment, both must keep the same TCP connection, so the one opened by
    /// the device with the larger id wins. Otherwise the new link wins, because a peer only reconnects when its
    /// old link has died.
    public static bool KeepsExisting(DeviceLink existing, DeviceLink incoming, string ownDeviceId)
    {
        if (!existing.IsOpen || (incoming.OpenedAt - existing.OpenedAt).Duration() > RaceWindow) return false;

        return string.CompareOrdinal(existing.OpenerId(ownDeviceId), incoming.OpenerId(ownDeviceId)) > 0;
    }

    public void Send(NetworkPacket packet)
    {
        if (IsOpen) outbox.Writer.TryWrite(packet.Serialize());
    }

    public void Close(string reason = "closed locally")
    {
        Record(reason);
        Shutdown();
    }

    internal void Start()
    {
        _ = Task.Run(ReadLoop);
        _ = Task.Run(WriteLoop);
    }

    /// Keeps the first reason: later ones are just the effects of it.
    internal void Record(string reason)
    {
        lock (gate) this.reason ??= reason;
    }

    private async Task ReadLoop()
    {
        try
        {
            while (await reader.ReadLineAsync(stop.Token).ConfigureAwait(false) is byte[] line)
            {
                if (line.Length == 0) continue;

                NetworkPacket packet;
                try
                {
                    packet = NetworkPacket.Parse(line);
                }
                catch (ProtocolException)
                {
                    continue;
                }

                Deliver(packet);
            }

            Record("peer closed the connection");
        }
        catch (Exception e) when (!stop.IsCancellationRequested)
        {
            Record($"read failed: {e.Message}");
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            Shutdown();
        }
    }

    private async Task WriteLoop()
    {
        try
        {
            await foreach (var data in outbox.Reader.ReadAllAsync(stop.Token).ConfigureAwait(false))
            {
                await stream.WriteAsync(data, stop.Token).ConfigureAwait(false);
                await stream.FlushAsync(stop.Token).ConfigureAwait(false);
            }
        }
        catch (Exception e) when (!stop.IsCancellationRequested)
        {
            Record($"write failed: {e.Message}");
            Shutdown();
        }
        catch (OperationCanceledException)
        {
        }
    }

    /// A failing feature must not take the connection down with it.
    private void Deliver(NetworkPacket packet)
    {
        try
        {
            OnPacket?.Invoke(packet);
        }
        catch (Exception e)
        {
            System.Diagnostics.Debug.WriteLine($"Packet {packet.Type} failed: {e}");
        }
    }

    private void Shutdown()
    {
        if (Interlocked.Exchange(ref closed, 1) == 1) return;

        stop.Cancel();
        outbox.Writer.TryComplete();
        stream.Dispose();
        connection.Dispose();
        OnClosed?.Invoke();
    }
}
