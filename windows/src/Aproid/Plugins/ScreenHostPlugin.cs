using Aproid.Core;
using Aproid.Shell;

namespace Aproid.Plugins;

/// Shows this PC's screen to a paired computer that asks for it ("flyylink.screen.request"), as JPEG pictures.
/// One computer watches at a time. It works the PC through "flyylink.input", which InputSharePlugin plays.
internal sealed class ScreenHostPlugin : IPlugin
{
    private readonly object gate = new();
    private ScreenShare? share;

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.ScreenRequest };

    /// Whether paired computers may see this screen. The same setting that lets them use the keyboard and mouse.
    public Func<bool> Allows { get; set; } = () => true;

    /// Called on a background thread with the computer now watching, or null.
    public Action<string?>? OnChange { get; set; }

    /// The computer watching this screen now, or null.
    public string? ViewerId
    {
        get
        {
            lock (gate) return share?.DeviceId;
        }
    }

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (Screen.RequestOf(packet) is not Screen.Request request || !device.Link.Identity.DeviceType.IsComputer()) return;

        if (request.Action == Screen.Action.Start) Start(device, (int)request.MaxSize);
        else Stop(device.Id);
    }

    /// Stops showing the screen to `deviceId`, or to anyone when null.
    public void Stop(string? deviceId = null)
    {
        ScreenShare? ended;
        lock (gate)
        {
            if (share is null || (deviceId is not null && share.DeviceId != deviceId)) return;

            ended = share;
            share = null;
        }

        ended.Dispose();
        OnChange?.Invoke(null);
    }

    private void Start(Device device, int maxSize)
    {
        Stop();

        if (!Allows())
        {
            device.Send(Screen.Stopped());
            return;
        }

        var started = new ScreenShare(device.Id, maxSize);
        started.OnEnd = () =>
        {
            lock (gate)
            {
                if (share != started) return;

                share = null;
            }
            OnChange?.Invoke(null);
        };
        lock (gate) share = started;

        started.Start(device);
        OnChange?.Invoke(device.Id);
    }

    /// One computer watching this screen: each new picture goes out on a live stream to it.
    private sealed class ScreenShare(string deviceId, int maxSize) : IDisposable
    {
        private readonly ScreenCapture capture = new(maxSize);
        private readonly LiveStream stream = new();
        private readonly long startedAt = Environment.TickCount64;
        private int ended;

        public string DeviceId { get; } = deviceId;

        /// Called once when the share ends by itself: the viewer left or the link broke.
        public Action? OnEnd { get; set; }

        public void Start(Device device)
        {
            capture.OnPicture = jpeg =>
            {
                var frame = new ScreenFrame(jpeg, (Environment.TickCount64 - startedAt) * 1000, ScreenFrame.Key);
                stream.Push([.. frame.Header(), .. frame.Data]);
            };

            var packet = Screen.Started(capture.Size.Width, capture.Size.Height, codec: Screen.Jpeg, platform: RemoteInput.Windows);
            if (!device.SendWithPayload(packet, PayloadTransfer.Stream, stream, completion: _ => End()))
            {
                End();
                return;
            }

            capture.Start();
        }

        public void Dispose()
        {
            Interlocked.Exchange(ref ended, 1);
            capture.Dispose();
            stream.Complete();
        }

        private void End()
        {
            if (Interlocked.Exchange(ref ended, 1) != 0) return;

            capture.Dispose();
            stream.Complete();
            OnEnd?.Invoke();
        }
    }
}
