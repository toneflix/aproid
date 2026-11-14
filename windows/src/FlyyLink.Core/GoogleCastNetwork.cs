using System.Buffers.Binary;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Text.Json.Nodes;

namespace FlyyLink.Core;

/// Finds Google Cast TVs over mDNS. Mirrors GoogleCastNetwork.kt and GoogleCastNetwork.swift.
public static class CastFinder
{
    /// Asks for the timeout and returns each TV once, sorted by name.
    public static async Task<List<TvRenderer>> SearchAsync(TimeSpan? timeout = null, CancellationToken cancel = default)
    {
        using var socket = new UdpClient(new IPEndPoint(IPAddress.Any, 0));
        var group = new IPEndPoint(IPAddress.Parse(Mdns.Address), Mdns.Port);
        var query = Mdns.Query();

        // Sent twice, since multicast over Wi-Fi drops packets.
        for (var i = 0; i < 2; i++)
        {
            try { await socket.SendAsync(query, group, cancel); } catch (SocketException) { }
        }

        var found = new Dictionary<string, TvRenderer>();
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        deadline.CancelAfter(timeout ?? TimeSpan.FromSeconds(3));

        while (true)
        {
            UdpReceiveResult result;
            try
            {
                result = await socket.ReceiveAsync(deadline.Token);
            }
            catch (Exception e) when (e is OperationCanceledException or SocketException)
            {
                break;
            }

            foreach (var tv in Mdns.CastTvs(Mdns.Parse(result.Buffer), result.RemoteEndPoint.Address.ToString())) found[tv.Id] = tv;
        }

        return found.Values.OrderBy(tv => tv.Name, StringComparer.OrdinalIgnoreCase).ToList();
    }
}

/// A TLS connection to a Cast TV that answers its heartbeats and matches replies to requests.
public sealed class CastChannel : IDisposable
{
    private sealed class Waiter(Func<JsonObject, bool> match)
    {
        public Func<JsonObject, bool> Match => match;

        public TaskCompletionSource<JsonObject> Reply { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    }

    private readonly TcpClient _client;
    private readonly SslStream _stream;
    private readonly SemaphoreSlim _writing = new(1, 1);
    private readonly List<Waiter> _waiters = [];
    private readonly CancellationTokenSource _stop = new();
    private int _nextId;

    public bool IsOpen => !_stop.IsCancellationRequested;

    private CastChannel(TcpClient client, SslStream stream)
    {
        _client = client;
        _stream = stream;
    }

    /// Connects and starts answering heartbeats.
    public static async Task<CastChannel> ConnectAsync(CastEndpoint endpoint)
    {
        var client = new TcpClient();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));

        try
        {
            await client.ConnectAsync(endpoint.Host, endpoint.Port, timeout.Token);

            // Cast TVs use self-signed certificates.
            var stream = new SslStream(client.GetStream(), false);
            await stream.AuthenticateAsClientAsync(
                new SslClientAuthenticationOptions { TargetHost = endpoint.Host, RemoteCertificateValidationCallback = (_, _, _, _) => true },
                timeout.Token);

            var channel = new CastChannel(client, stream);
            _ = channel.ReadLoopAsync();
            _ = channel.PingLoopAsync();

            return channel;
        }
        catch (Exception e) when (e is IOException or SocketException or AuthenticationException or OperationCanceledException)
        {
            client.Dispose();
            throw new ProtocolException($"couldn't connect to the TV: {e.Message}");
        }
    }

    public int NewRequestId() => Interlocked.Increment(ref _nextId);

    public async Task SendAsync(string ns, string destination, JsonObject payload)
    {
        var bytes = new CastMessage(GoogleCast.Sender, destination, ns, payload.ToJsonString()).Encode();
        var frame = new byte[4 + bytes.Length];
        BinaryPrimitives.WriteInt32BigEndian(frame, bytes.Length);
        bytes.CopyTo(frame, 4);

        await _writing.WaitAsync();
        try
        {
            await _stream.WriteAsync(frame);
            await _stream.FlushAsync();
        }
        catch (Exception e) when (e is IOException or ObjectDisposedException or NotSupportedException or InvalidOperationException)
        {
            throw new ProtocolException("lost the connection to the TV");
        }
        finally
        {
            _writing.Release();
        }
    }

    /// Sends the payload and waits for the first message that matches.
    public async Task<JsonObject> RequestAsync(string ns, string destination, JsonObject payload, Func<JsonObject, bool> match, TimeSpan? timeout = null)
    {
        var waiter = new Waiter(match);
        lock (_waiters)
        {
            if (!IsOpen) throw new ProtocolException("not connected to the TV");
            _waiters.Add(waiter);
        }

        try
        {
            await SendAsync(ns, destination, payload);

            var done = await Task.WhenAny(waiter.Reply.Task, Task.Delay(timeout ?? TimeSpan.FromSeconds(5)));
            if (done != waiter.Reply.Task) throw new ProtocolException($"the TV didn't answer {GoogleCast.Type(payload)}");

            return await waiter.Reply.Task;
        }
        finally
        {
            lock (_waiters) _waiters.Remove(waiter);
        }
    }

    public void Dispose()
    {
        List<Waiter> pending;
        lock (_waiters)
        {
            if (_stop.IsCancellationRequested) return;

            _stop.Cancel();
            pending = [.. _waiters];
        }

        _client.Dispose();
        foreach (var waiter in pending) waiter.Reply.TrySetException(new ProtocolException("the TV closed the connection"));
    }

    private async Task PingLoopAsync()
    {
        while (IsOpen)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), _stop.Token);
                await SendAsync(GoogleCast.Heartbeat, GoogleCast.Receiver, GoogleCast.Ping());
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (ProtocolException)
            {
            }
        }
    }

    private async Task ReadLoopAsync()
    {
        var head = new byte[4];

        try
        {
            while (IsOpen)
            {
                await _stream.ReadExactlyAsync(head, _stop.Token);
                var length = BinaryPrimitives.ReadInt32BigEndian(head);
                if (length is < 0 or > 1 << 20) break;

                var body = new byte[length];
                await _stream.ReadExactlyAsync(body, _stop.Token);

                if (CastMessage.Decode(body) is not CastMessage message || GoogleCast.Parse(message.Payload) is not JsonObject json) continue;

                var type = GoogleCast.Type(json);
                if (message.Namespace == GoogleCast.Heartbeat && type == "PING")
                {
                    try { await SendAsync(GoogleCast.Heartbeat, message.Source, GoogleCast.Pong()); } catch (ProtocolException) { }
                }
                else if (message.Namespace == GoogleCast.Connection && type == "CLOSE")
                {
                    break;
                }
                else
                {
                    Waiter? waiter;
                    lock (_waiters) waiter = _waiters.FirstOrDefault(w => !w.Reply.Task.IsCompleted && w.Match(json));
                    waiter?.Reply.TrySetResult(json);
                }
            }
        }
        catch (Exception e) when (e is IOException or OperationCanceledException or ObjectDisposedException or InvalidOperationException)
        {
        }
        finally
        {
            Dispose();
        }
    }
}

/// Plays on a Cast TV through its Default Media Receiver.
internal sealed class CastControl(CastEndpoint endpoint) : ITvControl
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private CastChannel? _channel;
    private CastApp? _app;
    private long? _mediaSessionId;
    private long _duration;

    public Task PlayAsync(string url, string title, string mime, long? size = null) => Locked(async () =>
    {
        _channel?.Dispose();

        var opened = await CastChannel.ConnectAsync(endpoint);
        _channel = opened;
        await opened.SendAsync(GoogleCast.Connection, GoogleCast.Receiver, GoogleCast.Connect());

        var id = opened.NewRequestId();
        var reply = await opened.RequestAsync(
            GoogleCast.ReceiverNamespace,
            GoogleCast.Receiver,
            GoogleCast.Launch(id),
            m => GoogleCast.MediaApp(m) is not null || (GoogleCast.RequestId(m) == id && GoogleCast.Failures.Contains(GoogleCast.Type(m) ?? "")),
            TimeSpan.FromSeconds(15));
        var launched = GoogleCast.MediaApp(reply) ?? throw new ProtocolException("the TV couldn't open its media player");

        _app = launched;
        _duration = 0;
        await opened.SendAsync(GoogleCast.Connection, launched.TransportId, GoogleCast.Connect());

        var loaded = await MediaAsync(r => GoogleCast.Load(r, url, title, mime), TimeSpan.FromSeconds(15));
        _mediaSessionId = GoogleCast.MediaOf(loaded)?.MediaSessionId;
        return true;
    });

    public Task ResumeAsync() => Locked(() => MediaAsync(r => GoogleCast.Play(r, Session())));

    public Task PauseAsync() => Locked(() => MediaAsync(r => GoogleCast.Pause(r, Session())));

    public Task StopAsync() => Locked(async () =>
    {
        if (_channel is not CastChannel opened) return true;

        if (_mediaSessionId is long session)
        {
            try { await MediaAsync(r => GoogleCast.Stop(r, session)); } catch (ProtocolException) { }
        }
        if (_app is CastApp running)
        {
            try { await ReceiverAsync(r => GoogleCast.StopApp(r, running.SessionId)); } catch (ProtocolException) { }
        }

        opened.Dispose();
        _channel = null;
        _app = null;
        return true;
    });

    public Task SeekAsync(long positionMs) => Locked(() => MediaAsync(r => GoogleCast.Seek(r, Session(), positionMs)));

    public Task<CastPosition?> PositionAsync() => Locked(async () =>
    {
        if (await StatusAsync() is not { Position: CastPosition at }) return null;

        if (at.Duration > 0) _duration = at.Duration;
        return (CastPosition?)new CastPosition(at.Position, _duration);
    });

    public Task<CastState?> StateAsync() => Locked(async () => _channel?.IsOpen != true ? CastState.Stopped : (await StatusAsync())?.State);

    public Task<int?> VolumeAsync() => Locked(async () => GoogleCast.Volume(await ReceiverAsync(GoogleCast.ReceiverStatus)));

    public Task SetVolumeAsync(int volume) => Locked(() => ReceiverAsync(r => GoogleCast.SetVolume(r, volume)));

    private async Task<CastMedia?> StatusAsync()
    {
        if (_channel?.IsOpen != true) return null;

        var status = GoogleCast.MediaOf(await MediaAsync(r => GoogleCast.MediaStatus(r)));
        if (status?.MediaSessionId is long id) _mediaSessionId = id;

        return status;
    }

    private long Session() => _mediaSessionId ?? throw new ProtocolException("nothing is playing on the TV");

    private Task<JsonObject> MediaAsync(Func<int, JsonObject> build, TimeSpan? timeout = null)
    {
        var target = _app ?? throw new ProtocolException("the TV's media player isn't open");

        return CallAsync(GoogleCast.Media, target.TransportId, build, timeout);
    }

    private Task<JsonObject> ReceiverAsync(Func<int, JsonObject> build) => CallAsync(GoogleCast.ReceiverNamespace, GoogleCast.Receiver, build, null);

    private async Task<JsonObject> CallAsync(string ns, string destination, Func<int, JsonObject> build, TimeSpan? timeout)
    {
        if (_channel is not { IsOpen: true } opened) throw new ProtocolException("not connected to the TV");

        var id = opened.NewRequestId();
        var payload = build(id);

        var reply = await opened.RequestAsync(ns, destination, payload, m => GoogleCast.RequestId(m) == id, timeout);
        if (GoogleCast.Type(reply) is string type && GoogleCast.Failures.Contains(type)) throw new ProtocolException($"the TV refused {GoogleCast.Type(payload)}");

        return reply;
    }

    private async Task<T> Locked<T>(Func<Task<T>> action)
    {
        await _gate.WaitAsync();
        try
        {
            return await action();
        }
        finally
        {
            _gate.Release();
        }
    }
}
