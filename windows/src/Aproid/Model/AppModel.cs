using System.Collections.ObjectModel;
using Aproid.Core;
using Aproid.Plugins;
using Microsoft.UI.Dispatching;

namespace Aproid.Model;

/// The app's state and actions: the network link, the connected devices, the features and what the panel shows.
/// Properties change on the UI thread.
public sealed class AppModel : Observable, IDeviceDelegate
{
    private const int RecentLimit = 20;

    private readonly DispatcherQueue ui;
    private readonly Settings settings = new(AppPaths.Settings);
    private readonly FileTrustStore trustStore = new(AppPaths.TrustedDevices);
    private readonly DeviceRegistry connected = new();
    private readonly ToastCenter toasts = new();
    private readonly PluginRouter plugins;
    private readonly BatteryPlugin battery;
    private readonly ClipboardPlugin clipboard;
    private readonly NotificationPlugin notifications;
    private readonly SharePlugin share;
    private LanLink? link;
    private DispatcherQueueTimer? timer;
    private DateOnly notificationsDay = DateOnly.FromDateTime(DateTime.Now);

    private IReadOnlyList<DeviceState> devices = [];
    private DeviceState? focused;
    private IReadOnlyList<DeviceState> others = [];
    private string? error;
    private DateTimeOffset? clipboardSyncedAt;
    private int notificationsToday;

    public AppModel(DispatcherQueue ui)
    {
        this.ui = ui;

        Identity = new DeviceIdentity
        {
            DeviceId = settings.DeviceId,
            DeviceName = DeviceIdentity.SanitizeName(System.Net.Dns.GetHostName()),
            DeviceType = Windows.System.Power.PowerManager.BatteryStatus == Windows.System.Power.BatteryStatus.NotPresent ? DeviceType.Desktop : DeviceType.Laptop,
        };

        battery = new BatteryPlugin(toasts) { OnChange = () => ui.TryEnqueue(Publish) };
        clipboard = new ClipboardPlugin(connected, ui) { OnSync = () => ClipboardSyncedAt = DateTimeOffset.Now };
        notifications = new NotificationPlugin(toasts, connected) { IsEnabled = settings.MirrorsNotifications };
        notifications.OnShown = () => ui.TryEnqueue(CountNotification);
        share = new SharePlugin(AppPaths.Downloads, new TransferStore(AppPaths.Transfers), toasts, clipboard);
        share.OnActivity = activity => ui.TryEnqueue(() => Record(activity));
        plugins = new PluginRouter([notifications, battery, clipboard, share]);

        share.Restore();
    }

    public DeviceIdentity Identity { get; }

    public bool NotificationsAvailable => toasts.IsAvailable;

    public IReadOnlyList<DeviceState> Devices
    {
        get => devices;
        private set
        {
            if (Set(ref devices, value)) Raise(nameof(HasOtherPhones));
        }
    }

    /// The device the big cards are about: one asking to pair first, then the chosen or first paired phone.
    public DeviceState? Focused
    {
        get => focused;
        private set
        {
            if (!Set(ref focused, value)) return;

            Raise(nameof(HasOtherPhones));
            Raise(nameof(ShowsSearching));
            Raise(nameof(ShowsPairing));
            Raise(nameof(ShowsPhone));
        }
    }

    /// Everything connected apart from the focused device.
    public IReadOnlyList<DeviceState> Others
    {
        get => others;
        private set
        {
            if (Set(ref others, value)) Raise(nameof(HasOthers));
        }
    }

    public string? Error
    {
        get => error;
        private set
        {
            if (Set(ref error, value)) Raise(nameof(HasError));
        }
    }

    public DateTimeOffset? ClipboardSyncedAt
    {
        get => clipboardSyncedAt;
        private set
        {
            if (Set(ref clipboardSyncedAt, value)) Raise(nameof(ClipboardSubtitle));
        }
    }

    public int NotificationsToday
    {
        get => notificationsToday;
        private set
        {
            if (Set(ref notificationsToday, value)) Raise(nameof(NotificationsSubtitle));
        }
    }

    public bool MirrorsNotifications
    {
        get => settings.MirrorsNotifications;
        set
        {
            if (settings.MirrorsNotifications == value) return;

            settings.MirrorsNotifications = value;
            notifications.IsEnabled = value;
            Raise();
            Raise(nameof(NotificationsSubtitle));
            Raise(nameof(PhoneSummary));
        }
    }

    public bool StartsWithWindows
    {
        get => Shell.Startup.IsEnabled;
        set
        {
            Shell.Startup.IsEnabled = value;
            Raise();
        }
    }

    public ObservableCollection<Activity> Recent { get; } = [];

    public bool ShowsSearching => Focused is null;

    public bool ShowsPairing => Focused is { IsPaired: false };

    public bool ShowsPhone => Focused is { IsPaired: true };

    public bool HasOthers => Others.Count > 0;

    /// Several phones are paired, so the panel offers to switch between them.
    public bool HasOtherPhones => OtherPhones.Count > 0;

    public IReadOnlyList<DeviceState> OtherPhones => Devices.Where(d => d.IsPaired && d.Id != Focused?.Id).ToList();

    public bool HasError => Error is not null;

    public bool HasRecent => Recent.Count > 0;

    public string ClipboardSubtitle => ClipboardSyncedAt is { } date ? $"Synced {RelativeTime.Text(date)}" : "Send it now";

    public string NotificationsSubtitle => !MirrorsNotifications ? "Paused" : NotificationsToday == 0 ? "On" : $"{NotificationsToday} today";

    public string PhoneSummary => $"{(MirrorsNotifications ? "Notifications on" : "Notifications paused")} · Clipboard synced";

    public string ThisComputer => $"This PC: {Identity.DeviceName}";

    /// Starts listening for phones. Call once, on the UI thread.
    public void Start()
    {
        var me = Identity;

        Task.Run(() =>
        {
            try
            {
                // Creating the certificate on first launch is slow, so keep it off the UI thread.
                var certificate = LoadCertificate(me.DeviceId);
                var lan = new LanLink(() => me, certificate, trustStore, deviceLink =>
                {
                    // Created right away on the network thread so no early packet is missed.
                    var device = new Device(deviceLink, certificate, trustStore) { Delegate = this };
                    device.Start();
                    ui.TryEnqueue(() => Add(device));
                }, id => connected[id]?.Link.IsOpen == true);
                lan.Start();

                ui.TryEnqueue(() => Started(lan));
            }
            catch (Exception e)
            {
                ui.TryEnqueue(() => Error = $"Could not start: {e.Message}");
            }
        });
    }

    public void Stop()
    {
        timer?.Stop();
        link?.Stop();
        foreach (var device in connected.All) device.Link.Close("Aproid quit");
        toasts.Unregister();
    }

    /// Something was copied on this PC.
    public void ClipboardChanged() => clipboard.Changed();

    public void RequestPair(string id) => connected[id]?.RequestPair();

    public void Accept(string id) => connected[id]?.Accept();

    public void Reject(string id) => connected[id]?.Reject();

    public void Unpair(string id) => connected[id]?.Unpair();

    /// Shows this phone in the panel when several are paired.
    public void Select(string id)
    {
        settings.SelectedPhone = id;
        Publish();
    }

    public void Ring(string id) => connected[id]?.Send(FindMyPhone.Request());

    public async void SendClipboard(string id)
    {
        if (connected[id] is not Device device) return;

        if (!await clipboard.SendAsync(device)) Record(new Activity(ActivityKind.Failed, "Clipboard is empty", "Copy some text first"));
    }

    public void SendFiles(IEnumerable<string> paths, string id)
    {
        if (connected[id] is not Device device) return;

        var files = paths.Where(File.Exists).ToList();
        Task.Run(() => files.ForEach(path => share.Send(path, device)));
    }

    /// Sends a web link to open on the phone, or other text to put on its clipboard.
    public void SendText(string text, string id)
    {
        if (connected[id] is not Device device) return;

        var trimmed = text.Trim();
        var isLink = Uri.TryCreate(trimmed, UriKind.Absolute, out var url) && (url.Scheme == Uri.UriSchemeHttp || url.Scheme == Uri.UriSchemeHttps);
        if (!device.Send(isLink ? Share.LinkPacket(url!.AbsoluteUri) : Share.TextPacket(trimmed))) return;

        Record(isLink
            ? new Activity(ActivityKind.Link, url!.Host, $"Opened on {device.Name}") { Url = url.AbsoluteUri }
            : new Activity(ActivityKind.Text, $"“{(trimmed.Length > 60 ? trimmed[..60] : trimmed)}”", $"Copied to {device.Name}"));
    }

    public void ClearRecent()
    {
        foreach (var done in Recent.Where(a => !a.IsInProgress).ToList()) Recent.Remove(done);

        Raise(nameof(HasRecent));
    }

    private void Record(Activity activity)
    {
        var index = Recent.ToList().FindIndex(a => a.Id == activity.Id);
        if (index >= 0)
        {
            Recent[index] = activity;
            return;
        }

        Recent.Insert(0, activity);
        while (Recent.Count > RecentLimit) Recent.RemoveAt(Recent.Count - 1);

        Raise(nameof(HasRecent));
    }

    private void CountNotification()
    {
        var today = DateOnly.FromDateTime(DateTime.Now);
        if (today != notificationsDay)
        {
            notificationsDay = today;
            NotificationsToday = 0;
        }

        NotificationsToday++;
    }

    private void Started(LanLink lan)
    {
        link = lan;
        timer = ui.CreateTimer();
        timer.Interval = TimeSpan.FromSeconds(5);
        timer.Tick += (_, _) =>
        {
            Task.Run(() => lan.BroadcastIdentity());
            foreach (var device in connected.All) device.Tick();
            Raise(nameof(ClipboardSubtitle));
        };
        timer.Start();

        Task.Run(() => lan.BroadcastIdentity());
    }

    private void Add(Device device)
    {
        if (connected[device.Id] is Device existing && existing != device && DeviceLink.KeepsExisting(existing.Link, device.Link, Identity.DeviceId))
        {
            device.Link.Close("both sides connected at once; kept the other link");
            return;
        }

        if (connected.Insert(device) is Device old && old != device) old.Link.Close("replaced by a newer link");
        if (device.IsPaired) plugins.OnPaired(device);

        Publish();
    }

    private void Remove(Device device)
    {
        if (connected.Remove(device)) Publish();
    }

    private void Publish()
    {
        Devices = connected.All
            .Select(device =>
            {
                var state = device.PairState;
                var showsCode = state is PairState.Requested or PairState.RequestedByPeer;

                return new DeviceState(
                    device.Id,
                    device.Name,
                    device.Link.Identity.DeviceType,
                    device.Link.Host,
                    state,
                    showsCode ? device.VerificationCode : null,
                    battery.Status(device.Id));
            })
            .OrderBy(d => d.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();

        Focused = Devices.FirstOrDefault(d => d.PairState is PairState.RequestedByPeer or PairState.Requested)
            ?? Devices.FirstOrDefault(d => d.IsPaired && d.Id == settings.SelectedPhone)
            ?? Devices.FirstOrDefault(d => d.IsPaired);
        Others = Devices.Where(d => d.Id != Focused?.Id).ToList();
    }

    private static DeviceCertificate LoadCertificate(string deviceId)
    {
        // Reuse the stored certificate only if it belongs to this device id. Peers refuse a certificate
        // whose common name differs from the id we announce.
        try
        {
            var stored = DeviceCertificate.FromPfx(File.ReadAllBytes(AppPaths.Certificate));
            if (stored.DeviceId == deviceId) return stored;
        }
        catch (Exception e) when (e is IOException or System.Security.Cryptography.CryptographicException or ProtocolException)
        {
        }

        var certificate = DeviceCertificate.Generate(deviceId);
        File.WriteAllBytes(AppPaths.Certificate, certificate.ExportPfx());

        return certificate;
    }

    // IDeviceDelegate, called on network threads.

    void IDeviceDelegate.DevicePairRequested(Device device, string code) => ui.TryEnqueue(() =>
    {
        Publish();
        PairRequested?.Invoke();
    });

    void IDeviceDelegate.DevicePairStateChanged(Device device, PairState state)
    {
        if (state == PairState.Paired) plugins.OnPaired(device);

        ui.TryEnqueue(Publish);
    }

    void IDeviceDelegate.DeviceReceived(Device device, NetworkPacket packet) => plugins.Dispatch(packet, device);

    void IDeviceDelegate.DeviceDisconnected(Device device) => ui.TryEnqueue(() => Remove(device));

    /// A phone asked to pair, so the panel should open.
    public event Action? PairRequested;
}
