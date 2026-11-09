using System.Net;
using System.Net.Security;
using System.Net.Sockets;

namespace Aproid.Core;

/// Moves a packet's payload, such as a file, over its own TLS connection, as KDE Connect does.
/// The sender opens a port and acts as the TLS server; the receiver connects as the client.
/// Each side checks the other's certificate against the one from the device link.
/// Mirrors PayloadTransfer.kt and PayloadTransfer.swift.
public sealed class PayloadTransfer(DeviceCertificate certificate, PortRange? ports = null)
{
    /// Payload size that marks a live stream, read until the sender closes it.
    public const long Stream = -1;

    // Large reads keep a fast Wi-Fi link full instead of waiting on small writes.
    private const int ChunkSize = 256 * 1024;

    private static readonly TimeSpan OfferTimeout = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(10);

    private readonly PortRange range = ports ?? Protocol.PayloadPorts;

    /// Opens a port and streams `source` to the first peer that connects with `peerCertificateDer`.
    /// `onProgress` gets each piece's byte count once it is written. Returns the port to put in the packet.
    public int Offer(byte[] peerCertificateDer, System.IO.Stream source, Action<long>? onProgress = null, Action<Exception?>? completion = null)
    {
        Exception last = new ProtocolException($"no free payload port in {range.First}...{range.Last}");

        foreach (var port in range.All)
        {
            var listener = new TcpListener(IPAddress.Any, port);
            try
            {
                listener.Start();
            }
            catch (SocketException e)
            {
                last = e;
                continue;
            }

            _ = ServeAsync(listener, peerCertificateDer, source, onProgress, completion ?? (_ => { }));

            return port;
        }

        throw last;
    }

    /// Downloads `size` bytes that the peer offered at `host`:`port` into `sink`.
    public async Task ReceiveAsync(
        string host,
        int port,
        long size,
        byte[] peerCertificateDer,
        System.IO.Stream sink,
        Action<long>? onProgress = null,
        CancellationToken cancellation = default)
    {
        await DownloadAsync(host, port, size, peerCertificateDer, async data =>
        {
            await sink.WriteAsync(data, cancellation).ConfigureAwait(false);
            onProgress?.Invoke(data.Length);
        }, cancellation).ConfigureAwait(false);

        await sink.FlushAsync(cancellation).ConfigureAwait(false);
    }

    /// Reads a live stream and hands each piece to `onData` until the peer closes it.
    public Task StreamAsync(string host, int port, byte[] peerCertificateDer, Func<ReadOnlyMemory<byte>, ValueTask> onData, CancellationToken cancellation = default) =>
        DownloadAsync(host, port, Stream, peerCertificateDer, onData, cancellation);

    private async Task ServeAsync(TcpListener listener, byte[] expected, System.IO.Stream source, Action<long>? onProgress, Action<Exception?> done)
    {
        TcpClient client;
        try
        {
            using var wait = new CancellationTokenSource(OfferTimeout);
            client = await listener.AcceptTcpClientAsync(wait.Token).ConfigureAwait(false);
        }
        catch (Exception)
        {
            source.Dispose();
            done(new ProtocolException("the peer never downloaded the payload"));
            return;
        }
        finally
        {
            // One download per offer.
            listener.Stop();
        }

        try
        {
            using (client)
            using (source)
            {
                var peer = new PeerCertificate();
                await using var tls = new SslStream(client.GetStream(), leaveInnerStreamOpen: false);
                using (var handshake = new CancellationTokenSource(ConnectTimeout))
                {
                    await tls.AuthenticateAsServerAsync(PeerCertificate.ServerOptions(certificate, peer), handshake.Token).ConfigureAwait(false);
                }

                if (peer.Der is null || !peer.Der.AsSpan().SequenceEqual(expected)) throw new ProtocolException("payload peer is not the paired device");

                var buffer = new byte[ChunkSize];
                int read;
                while ((read = await source.ReadAsync(buffer).ConfigureAwait(false)) > 0)
                {
                    await tls.WriteAsync(buffer.AsMemory(0, read)).ConfigureAwait(false);
                    onProgress?.Invoke(read);
                }

                await tls.FlushAsync().ConfigureAwait(false);
                await tls.ShutdownAsync().ConfigureAwait(false);
            }

            done(null);
        }
        catch (Exception e)
        {
            done(e);
        }
    }

    private async Task DownloadAsync(
        string host,
        int port,
        long size,
        byte[] expected,
        Func<ReadOnlyMemory<byte>, ValueTask> write,
        CancellationToken cancellation)
    {
        var isStream = size == Stream;
        using var client = new TcpClient(AddressFamily.InterNetwork);
        var peer = new PeerCertificate();

        using (var connect = CancellationTokenSource.CreateLinkedTokenSource(cancellation))
        {
            connect.CancelAfter(ConnectTimeout);
            await client.ConnectAsync(host, port, connect.Token).ConfigureAwait(false);
        }

        await using var tls = new SslStream(client.GetStream(), leaveInnerStreamOpen: false);
        using (var handshake = CancellationTokenSource.CreateLinkedTokenSource(cancellation))
        {
            handshake.CancelAfter(ConnectTimeout);
            await tls.AuthenticateAsClientAsync(PeerCertificate.ClientOptions(certificate, peer, host), handshake.Token).ConfigureAwait(false);
        }

        if (peer.Der is null || !peer.Der.AsSpan().SequenceEqual(expected)) throw new ProtocolException("payload peer is not the paired device");

        var buffer = new byte[ChunkSize];
        long received = 0;

        while (isStream || received < size)
        {
            var wanted = isStream ? buffer.Length : (int)Math.Min(buffer.Length, size - received);
            int read;
            try
            {
                read = await tls.ReadAsync(buffer.AsMemory(0, wanted), cancellation).ConfigureAwait(false);
            }
            catch (IOException) when (isStream)
            {
                return;
            }

            if (read == 0)
            {
                if (isStream) return;
                throw new ProtocolException($"payload ended after {received} of {size} bytes");
            }

            await write(buffer.AsMemory(0, read)).ConfigureAwait(false);
            received += read;
        }
    }
}
