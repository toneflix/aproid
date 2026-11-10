using System.Net;
using System.Net.NetworkInformation;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;

namespace Aproid.Core;

/// LAN discovery and connection setup from the KDE Connect protocol.
///
/// 1. We broadcast our identity over UDP to port 1716.
/// 2. A peer that hears it opens a TCP connection to our tcpPort and sends its identity.
/// 3. The socket is upgraded to TLS. The side that opened the TCP connection is the TLS server.
/// 4. With protocol v8, both sides send their identity again over TLS.
///
/// Mirrors LanLink.kt and LanLink.swift.
public sealed class LanLink(
    Func<DeviceIdentity> identityProvider,
    DeviceCertificate certificate,
    ITrustStore trustStore,
    Action<DeviceLink> onLink,
    Func<string, bool>? isConnected = null,
    int udpPort = Protocol.UdpPort,
    PortRange? tcpPorts = null) : IDisposable
{
    private static readonly TimeSpan HandshakeTimeout = TimeSpan.FromSeconds(10);

    private readonly PortRange ports = tcpPorts ?? Protocol.TcpPorts;
    private readonly Func<string, bool> isConnected = isConnected ?? (_ => false);
    private CancellationTokenSource? running;
    private TcpListener? listener;
    private UdpClient? discovery;

    /// Port the TCP listener is bound to, once started.
    public int? TcpPort { get; private set; }

    internal string OwnDeviceId => identityProvider().DeviceId;

    /// Binds the TCP listener and the UDP discovery port.
    public void Start()
    {
        running = new CancellationTokenSource();
        listener = BindTcp();
        TcpPort = ((IPEndPoint)listener.LocalEndpoint).Port;
        _ = AcceptLoop(listener, running.Token);

        // If the port is taken (for example by KDE Connect) we can still be found over TCP.
        try
        {
            discovery = new UdpClient(AddressFamily.InterNetwork);
            discovery.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            discovery.Client.Bind(new IPEndPoint(IPAddress.Any, udpPort));
            _ = DiscoveryLoop(discovery, running.Token);
        }
        catch (SocketException)
        {
            discovery?.Dispose();
            discovery = null;
        }
    }

    public void Stop()
    {
        running?.Cancel();
        listener?.Stop();
        discovery?.Dispose();
        listener = null;
        discovery = null;
        TcpPort = null;
    }

    public void Dispose() => Stop();

    /// Sends our identity to everyone on the local network: the global broadcast address, plus each network's own,
    /// since Windows sends the global one out of a single adapter.
    public void BroadcastIdentity(string? address = null)
    {
        var data = CurrentIdentity().ToPacket().Serialize();
        var targets = address is null ? BroadcastAddresses() : [IPAddress.Parse(address)];

        using var udp = new UdpClient(AddressFamily.InterNetwork) { EnableBroadcast = true };
        foreach (var target in targets)
        {
            try
            {
                udp.Send(data, data.Length, new IPEndPoint(target, udpPort));
            }
            catch (SocketException)
            {
            }
        }
    }

    /// Connects to a peer that announced itself. The link arrives through `onLink`.
    public async Task ConnectAsync(DeviceIdentity peer, string host)
    {
        if (peer.TcpPort is not int port) throw new ProtocolException("peer did not send tcpPort");

        var client = new TcpClient(AddressFamily.InterNetwork);
        using var timeout = new CancellationTokenSource(HandshakeTimeout);

        try
        {
            await client.ConnectAsync(host, port, timeout.Token).ConfigureAwait(false);
            var network = client.GetStream();
            await network.WriteAsync(CurrentIdentity().ToPacket().Serialize(), timeout.Token).ConfigureAwait(false);

            // We opened the connection, so we are the TLS server.
            var peerCertificate = new PeerCertificate();
            var tls = new SslStream(network, leaveInnerStreamOpen: false);
            await tls.AuthenticateAsServerAsync(PeerCertificate.ServerOptions(certificate, peerCertificate), timeout.Token).ConfigureAwait(false);
            await OpenAsync(client, tls, peerCertificate, peer, host, isOutgoing: true, timeout.Token).ConfigureAwait(false);
        }
        catch
        {
            client.Dispose();
            throw;
        }
    }

    /// Connects to a peer that announced itself over UDP, unless we already have a link to it.
    /// Peers announce every few seconds, and reconnecting each time would drop the working link.
    public bool HandleAnnouncement(DeviceIdentity peer, string host)
    {
        if (peer.DeviceId == OwnDeviceId || isConnected(peer.DeviceId)) return false;

        Observe(ConnectAsync(peer, host));

        return true;
    }

    internal DeviceIdentity CurrentIdentity() => identityProvider() with { TcpPort = TcpPort };

    internal void CheckCertificate(byte[] der, string deviceId)
    {
        if (DeviceCertificate.CommonName(der) != deviceId) throw new ProtocolException("certificate does not match device id");

        if (trustStore.Certificate(deviceId) is byte[] trusted && !trusted.AsSpan().SequenceEqual(der))
            throw new ProtocolException("certificate changed for a paired device");
    }

    private TcpListener BindTcp()
    {
        Exception last = new ProtocolException($"no free TCP port in {ports.First}...{ports.Last}");

        foreach (var port in ports.All)
        {
            var candidate = new TcpListener(IPAddress.Any, port);
            try
            {
                candidate.Start();
                return candidate;
            }
            catch (SocketException e)
            {
                last = e;
            }
        }

        throw last;
    }

    private async Task AcceptLoop(TcpListener server, CancellationToken cancellation)
    {
        while (!cancellation.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await server.AcceptTcpClientAsync(cancellation).ConfigureAwait(false);
            }
            catch (Exception e) when (e is OperationCanceledException or ObjectDisposedException or SocketException)
            {
                if (cancellation.IsCancellationRequested) return;
                continue;
            }

            Observe(AcceptAsync(client));
        }
    }

    /// The peer opened the connection and sent its identity: we act as the TLS client.
    private async Task AcceptAsync(TcpClient client)
    {
        using var timeout = new CancellationTokenSource(HandshakeTimeout);

        try
        {
            var network = client.GetStream();
            var line = await LineReader.ReadPlainLineAsync(network, 64 * 1024, timeout.Token).ConfigureAwait(false);
            var identity = DeviceIdentity.FromPacket(NetworkPacket.Parse(line));
            if (identity.DeviceId == OwnDeviceId) throw new ProtocolException("connected to ourselves");

            var host = (client.Client.RemoteEndPoint as IPEndPoint)?.Address is IPAddress address
                ? (address.IsIPv4MappedToIPv6 ? address.MapToIPv4() : address).ToString()
                : "";
            var peerCertificate = new PeerCertificate();
            var tls = new SslStream(network, leaveInnerStreamOpen: false);
            await tls.AuthenticateAsClientAsync(PeerCertificate.ClientOptions(certificate, peerCertificate, identity.DeviceId), timeout.Token).ConfigureAwait(false);
            await OpenAsync(client, tls, peerCertificate, identity, host, isOutgoing: false, timeout.Token).ConfigureAwait(false);
        }
        catch
        {
            client.Dispose();
            throw;
        }
    }

    /// Checks the certificate, swaps v8 identities, then hands the link over.
    private async Task OpenAsync(
        TcpClient client,
        SslStream tls,
        PeerCertificate peerCertificate,
        DeviceIdentity plainIdentity,
        string host,
        bool isOutgoing,
        CancellationToken cancellation)
    {
        if (peerCertificate.Der is not byte[] der) throw new ProtocolException("peer sent no certificate");

        CheckCertificate(der, plainIdentity.DeviceId);

        using var parsed = new X509Certificate2(der);
        var publicKey = DeviceCertificate.PublicKeyOf(parsed);
        var reader = new LineReader(tls);
        var identity = plainIdentity;

        if (plainIdentity.ProtocolVersion >= 8)
        {
            await tls.WriteAsync(CurrentIdentity().ToPacket().Serialize(), cancellation).ConfigureAwait(false);
            await tls.FlushAsync(cancellation).ConfigureAwait(false);

            var line = await reader.ReadLineAsync(cancellation).ConfigureAwait(false) ?? throw new ProtocolException("closed before identity");
            identity = DeviceIdentity.FromPacket(NetworkPacket.Parse(line));
            if (identity.DeviceId != plainIdentity.DeviceId) throw new ProtocolException("identity changed after TLS");
        }

        var link = new DeviceLink(identity, der, publicKey, host, isOutgoing, tls, client, reader);
        onLink(link);
        link.Start();
    }

    private async Task DiscoveryLoop(UdpClient udp, CancellationToken cancellation)
    {
        while (!cancellation.IsCancellationRequested)
        {
            UdpReceiveResult received;
            try
            {
                received = await udp.ReceiveAsync(cancellation).ConfigureAwait(false);
            }
            catch (Exception e) when (e is OperationCanceledException or ObjectDisposedException)
            {
                return;
            }
            catch (SocketException)
            {
                // Windows reports an ICMP "port unreachable" from an earlier send as a receive error.
                continue;
            }

            try
            {
                var identity = DeviceIdentity.FromPacket(NetworkPacket.Parse(received.Buffer));
                HandleAnnouncement(identity, received.RemoteEndPoint.Address.ToString());
            }
            catch (ProtocolException)
            {
            }
        }
    }

    internal static List<IPAddress> BroadcastAddresses()
    {
        var addresses = new List<IPAddress> { IPAddress.Broadcast };

        try
        {
            foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (adapter.OperationalStatus != OperationalStatus.Up || adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;

                foreach (var unicast in adapter.GetIPProperties().UnicastAddresses)
                {
                    if (unicast.Address.AddressFamily != AddressFamily.InterNetwork || unicast.IPv4Mask is null) continue;

                    var ip = unicast.Address.GetAddressBytes();
                    var mask = unicast.IPv4Mask.GetAddressBytes();
                    var broadcast = new byte[4];
                    for (var i = 0; i < 4; i++) broadcast[i] = (byte)(ip[i] | ~mask[i]);

                    var target = new IPAddress(broadcast);
                    if (!addresses.Contains(target)) addresses.Add(target);
                }
            }
        }
        catch (NetworkInformationException)
        {
        }

        return addresses;
    }

    /// Connection attempts run in the background, and a failed one is simply dropped.
    private static void Observe(Task task) =>
        task.ContinueWith(t => _ = t.Exception, TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously);
}
