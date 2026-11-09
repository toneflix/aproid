using System.Security.Cryptography.X509Certificates;
using System.Collections.ObjectModel;
using Aproid.Core;
using Aproid.Plugins;
using Aproid.Shell;
using Microsoft.UI.Dispatching;
using Microsoft.Windows.AppNotifications.Builder;

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
    private readonly MediaPlugin media = new();
    private readonly SmsPlugin sms = new();
    private readonly CallPlugin calls = new();
    private readonly LocationPlugin locations = new();
    private readonly PhotosPlugin photos = new();
    private readonly ScreenPlugin screen = new();
    private LanLink? link;
    private DispatcherQueueTimer? timer;
    private DateOnly notificationsDay = DateOnly.FromDateTime(DateTime.Now);

    private IReadOnlyList<DeviceState> devices = [];
    private DeviceState? focused;
    private IReadOnlyList<DeviceState> others = [];
    private string? error;
    private DateTimeOffset? clipboardSyncedAt;
    private int notificationsToday;
    private ActiveCall? call;
    private string? finding;
    private string? messagesDevice;
    private readonly List<string> waitingFiles = [];
    private string? waitingNumber;
    private DateTimeOffset waitingSince;
    private readonly PhoneHotspot hotspot;
    private readonly Updater updater;
    private readonly PhoneFolder folder = new(AppPaths.PhonePhotos, AppPaths.PhonePhotosRecord);
    private Device? folderPhone;
    private NearbyFinder? nearby;
    private DateTimeOffset lastNearbySearch = DateTimeOffset.MinValue;
    private bool phoneNearby;
    private string? hotspotStatus;

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
        media.OnChange = () => ui.TryEnqueue(Publish);
        locations.OnChange = () => ui.TryEnqueue(Publish);
        sms.OnMessages = (messages, deviceId) => ui.TryEnqueue(() => Messages.Ingest(messages, deviceId));
        calls.OnState = (state, device) =>
        {
            var deviceId = device.Id;
            var deviceName = device.Name;
            ui.TryEnqueue(() => HandleCall(state, deviceId, deviceName));
        };
        photos.OnPage = (page, deviceId) => ui.TryEnqueue(() => Photos.Ingest(page, deviceId));
        photos.OnPreview = (id, file, deviceId) =>
        {
            if (deviceId == folderPhone?.Id) folder.Delivered(id, file);
            ui.TryEnqueue(() => Photos.IngestPreview(id, file, deviceId));
        };
        folder.Request = id => folderPhone is Device phone && phone.Send(Photos.DownloadPacket(id, preview: true));
        Photos.Arrived += arrived =>
        {
            if (!ShowsPhotosInExplorer) return;

            Task.Run(() => folder.Add(arrived));
            FillPhoneFolder();
        };
        Messages.Send = packet => Primary is Device phone && phone.Send(packet);
        Messages.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(MessagesStore.UnreadCount)) Raise(nameof(MessagesSubtitle));
        };
        Photos.Send = packet => Primary is Device phone && phone.Send(packet);
        screen.OnStarted = (device, info) =>
        {
            // Reset now, on the network thread, so the stream's first frames aren't lost.
            Video.Reset();
            var (id, name) = (device.Id, device.Name);
            ui.TryEnqueue(() =>
            {
                Mirror.Started(id, name, info.Width, info.Height);
                ScreenStarted?.Invoke(Video.CreateSource((uint)Math.Max(info.Width, 0), (uint)Math.Max(info.Height, 0)));
            });
        };
        screen.OnFrame = frame => Video.Push(frame);
        screen.OnEnded = id => ui.TryEnqueue(() => Mirror.Ended(id));
        Mirror.Send = (id, packet) => connected[id]?.Send(packet) == true;
        plugins = new PluginRouter([notifications, battery, clipboard, share, media, sms, calls, locations, photos, screen]);

        updater = new Updater(toasts) { OnInstalling = () => ui.TryEnqueue(() => UpdateInstalling?.Invoke()) };
        hotspot = new PhoneHotspot(() => settings.PhoneHotspots, settings.RememberHotspot);

        share.Restore();
    }

    public DeviceIdentity Identity { get; }

    public MessagesStore Messages { get; } = new();

    public PhotosStore Photos { get; } = new();

    public ScreenMirror Mirror { get; } = new();

    internal ScreenVideo Video { get; } = new();

    /// The call the call card shows.
    public ActiveCall? Call
    {
        get => call;
        private set => Set(ref call, value);
    }

    /// The phone being looked for: its map shows in the panel until closed.
    public string? Finding
    {
        get => finding;
        private set
        {
            if (Set(ref finding, value)) Raise(nameof(Found));
        }
    }

    /// The focused phone's location while it is being looked for.
    public PhoneLocation? Found => Focused is { } phone && phone.Id == Finding ? phone.Location : null;

    public string MessagesSubtitle => Messages.UnreadCount == 0 ? "Your texts" : $"{Messages.UnreadCount} unread";

    public bool NotificationsAvailable => toasts.IsAvailable;

    public IReadOnlyList<DeviceState> Devices
    {
        get => devices;
        private set
        {
            if (!Set(ref devices, value)) return;

            Raise(nameof(HasOtherPhones));
            Raise(nameof(NextPhone));
            Raise(nameof(ShowsCarousel));
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
            Raise(nameof(NextPhone));
            Raise(nameof(ShowsCarousel));
            Raise(nameof(ShowsSearching));
            Raise(nameof(ShowsHotspot));
            Raise(nameof(ShowsPairing));
            Raise(nameof(ShowsPhone));
            Raise(nameof(Found));
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

    public PhoneSwitcherStyle SwitcherStyle
    {
        get => settings.SwitcherStyle;
        set
        {
            if (settings.SwitcherStyle == value) return;

            settings.SwitcherStyle = value;
            Raise();
            Raise(nameof(ShowsCarousel));
        }
    }

    /// The paired phone after the one shown, wrapping round, when there is more than one.
    public DeviceState? NextPhone => new DeviceFocus(Focused?.Id).Next(Devices.Where(d => d.IsPaired), d => d.Id, d => d.Name) is { } next && next.Id != Focused?.Id ? next : null;

    public bool ShowsCarousel => SwitcherStyle == PhoneSwitcherStyle.Carousel && NextPhone is not null;

    public void ShowNextPhone()
    {
        if (NextPhone is DeviceState next) Select(next.Id);
    }

    /// Whether the keyboard shortcut opens the panel. The app turns the shortcut itself on and off.
    public bool OpensWithHotkey
    {
        get => settings.OpensWithHotkey;
        set
        {
            settings.OpensWithHotkey = value;
            Raise();
        }
    }

    /// Whether the phone's recent photos show as a folder in Explorer.
    public bool ShowsPhotosInExplorer
    {
        get => settings.ShowsPhotosInExplorer;
        set
        {
            settings.ShowsPhotosInExplorer = value;
            Raise();

            if (!value)
            {
                Task.Run(folder.Remove);
                return;
            }

            SyncStores(Primary);
            var loaded = Photos.Loaded.ToList();
            Task.Run(() => folder.Add(loaded));
            FillPhoneFolder();
        }
    }

    public string PhonePhotosFolder => folder.Root;

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

    /// A paired phone is in Bluetooth range but not on this network.
    public bool PhoneNearby
    {
        get => phoneNearby;
        private set
        {
            if (Set(ref phoneNearby, value)) Raise(nameof(ShowsHotspot));
        }
    }

    /// What joining the phone's hotspot is doing, or why it failed.
    public string? HotspotStatus
    {
        get => hotspotStatus;
        private set
        {
            if (!Set(ref hotspotStatus, value)) return;

            Raise(nameof(ShowsHotspot));
            Raise(nameof(IsJoiningHotspot));
            Raise(nameof(CanJoinHotspot));
            Raise(nameof(HotspotText));
        }
    }

    public bool ShowsHotspot => Focused is null && (PhoneNearby || HotspotStatus is not null);

    public bool IsJoiningHotspot => HotspotStatus is not null;

    public bool CanJoinHotspot => HotspotStatus is null;

    public string HotspotText => HotspotStatus ?? (PhoneHotspotName is null
        ? "It isn't on this Wi-Fi. Use its hotspot to get online and connect; this PC leaves its current network."
        : "It isn't on this Wi-Fi. Your phone shows a switch to turn its hotspot on, and this PC joins it.");

    /// The name of the phone's hotspot, once this PC has been on it.
    public string? PhoneHotspotName => HotspotPhoneId is string id ? hotspot.Name(id) : null;

    public string HotspotButton => PhoneHotspotName is string ssid ? $"Use {ssid}" : "Use phone's hotspot";

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
                nearby = new NearbyFinder(me.DeviceId, certificate.Certificate.GetRSAPrivateKey()!)
                {
                    OnNearby = found => ui.TryEnqueue(() => PhoneNearby = found && connected.Paired.Count == 0),
                    OnAnswer = answer => ui.TryEnqueue(() => Reach(answer)),
                };
                var lan = new LanLink(() => me, certificate, trustStore, deviceLink =>
                {
                    // Created right away on the network thread so no early packet is missed.
                    var device = new Device(deviceLink, certificate, trustStore) { Delegate = this };
                    device.Start();
                    ui.TryEnqueue(() => Add(device));
                }, id => connected[id]?.Link.IsOpen == true);
                lan.Start();

                ui.TryEnqueue(() => Started(lan));
                updater.Start();
            }
            catch (Exception e)
            {
                ui.TryEnqueue(() => Error = $"Could not start: {e.Message}");
            }
        });
    }

    /// The installer for a new version is running; quit so it can replace the app.
    public event Action? UpdateInstalling;

    public string VersionText => Updater.CurrentText;

    public void CheckForUpdates() => _ = updater.CheckAsync(manual: true);

    public void Stop()
    {
        timer?.Stop();
        link?.Stop();
        folder.Disconnect();
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

    /// Rings the phone and asks where it is, so it can be found by sound or on the map.
    public void Ring(string id)
    {
        if (connected[id] is not Device device) return;

        device.Send(FindMyPhone.Request());
        locations.Request(device);
        Finding = id;
    }

    public void StopFinding() => Finding = null;

    public void Control(string id, string player, MediaAction action) => connected[id]?.Send(MediaRequest.Act(player, action).ToPacket());

    public void Seek(string id, string player, long position) => connected[id]?.Send(MediaRequest.Seek(player, position).ToPacket());

    // Calls

    public void AnswerCall()
    {
        if (Call is { } current) connected[current.DeviceId]?.Send(Core.Call.Answer());
    }

    public void DeclineCall()
    {
        if (Call is not { } current) return;

        connected[current.DeviceId]?.Send(Core.Call.Decline());
        EndCall();
    }

    public void HangUp()
    {
        if (Call is not { } current) return;

        connected[current.DeviceId]?.Send(Core.Call.HangUp());
        EndCall();
    }

    /// Mutes the phone's microphone during a call.
    public void ToggleMute()
    {
        if (Call is not { } current) return;

        var muted = !current.IsMuted;
        connected[current.DeviceId]?.Send(Core.Call.Mute(muted));
        Call = current with { IsMuted = muted };
    }

    /// Places a call on the phone the panel shows.
    public void Dial(string number, string? name = null)
    {
        var trimmed = number.Trim();
        if (trimmed.Length == 0) return;

        if (Primary is not Device phone || !phone.Send(Core.Call.Dial(trimmed)))
        {
            Record(new Activity(ActivityKind.Failed, $"Couldn't call {trimmed}", "Connect your phone first"));
            return;
        }

        Call = new ActiveCall(phone.Id, phone.Name, trimmed, name, null, CallPhase.Dialing);
    }

    private void HandleCall(Core.Call.State state, string deviceId, string deviceName)
    {
        if (state.Ended)
        {
            EndCall();
            return;
        }

        switch (state.Event)
        {
            case CallEvent.Ringing:
                Call = new ActiveCall(deviceId, deviceName, state.Number, state.ContactName, state.Photo, CallPhase.Ringing);
                break;
            case CallEvent.Talking:
                var current = Call ?? new ActiveCall(deviceId, deviceName, state.Number, state.ContactName, state.Photo, CallPhase.Dialing);
                Call = current.Phase == CallPhase.Talking ? current : current with { Phase = CallPhase.Talking, Since = DateTimeOffset.Now };
                break;
            case CallEvent.Missed:
                EndCall();
                AnnounceMissedCall(state.ContactName ?? state.Number, state.Number, deviceName);
                break;
        }
    }

    private void EndCall()
    {
        if (Call is { IsMuted: true } muted) connected[muted.DeviceId]?.Send(Core.Call.Mute(false));

        Call = null;
    }

    private void AnnounceMissedCall(string caller, string number, string deviceName) => toasts.Show(
        key => new AppNotificationBuilder()
            .AddText("Missed call")
            .AddText(caller)
            .SetAttributionText(deviceName)
            .AddButton(ToastCenter.Button("Call back", "call", key))
            .AddButton(ToastCenter.Button("Message", "text", key)),
        (action, _) => ui.TryEnqueue(() =>
        {
            if (action == "call") Dial(number, caller == number ? null : caller);
            else if (action == "text") ShowMessages(number);
        }));

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

    /// Files and tel: links handed over by Windows. Right after Aproid starts no phone is connected yet,
    /// so they wait up to a minute for one.
    public void Handover(IReadOnlyList<string> files, string? number)
    {
        waitingFiles.AddRange(files);
        waitingNumber = number ?? waitingNumber;
        waitingSince = DateTimeOffset.Now;

        SendWaiting();
    }

    private void SendWaiting()
    {
        if (waitingFiles.Count == 0 && waitingNumber is null) return;

        if (Primary is Device phone)
        {
            if (waitingFiles.Count > 0) SendFiles(waitingFiles.ToList(), phone.Id);
            if (waitingNumber is string number) Dial(number);
        }
        else if (DateTimeOffset.Now - waitingSince < TimeSpan.FromMinutes(1))
        {
            return;
        }
        else
        {
            Record(new Activity(ActivityKind.Failed, "Nothing was sent", "No phone connected. Open Aproid on your phone and try again."));
        }

        waitingFiles.Clear();
        waitingNumber = null;
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
            SendWaiting();
            SearchNearbyIfLost();
            FillPhoneFolder();
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
        if (device.IsPaired)
        {
            plugins.OnPaired(device);
            PhoneNearby = false;
            HotspotStatus = null;
            hotspot.Cancel();
            LearnHotspot(device);
        }

        Publish();
    }

    /// Looks for a paired phone over Bluetooth when none is on this network.
    private void SearchNearbyIfLost()
    {
        var lost = connected.Paired.Count == 0 && trustStore.TrustedIds.Count > 0;
        if (!lost || DateTimeOffset.Now - lastNearbySearch < TimeSpan.FromSeconds(45)) return;

        lastNearbySearch = DateTimeOffset.Now;
        nearby?.Search(Nearby.Want.Connect);
    }

    private string? HotspotPhoneId => new[] { settings.SelectedPhone }
        .Concat(trustStore.TrustedIds)
        .FirstOrDefault(id => id is not null && hotspot.Name(id) is not null);

    /// Asks the phone to turn its hotspot on, then joins it when it shows up. This PC leaves its current Wi-Fi.
    public void JoinPhoneHotspot()
    {
        lastNearbySearch = DateTimeOffset.Now;
        nearby?.Search(Nearby.Want.Hotspot);

        if (HotspotPhoneId is not string id)
        {
            HotspotStatus = "Turn on the hotspot on your phone, then pick it in the Wi-Fi menu. Aproid remembers it for next time.";
            return;
        }

        HotspotStatus = "Asking your phone to turn on its hotspot…";
        hotspot.Join(id, status => ui.TryEnqueue(() => HotspotChanged(status)));
    }

    public void CancelHotspot()
    {
        hotspot.Cancel();
        HotspotStatus = null;
    }

    private void HotspotChanged(PhoneHotspot.Status? status)
    {
        if (HotspotStatus is null) return;

        HotspotStatus = status switch
        {
            PhoneHotspot.Status.Waiting waiting => $"Waiting for {waiting.Ssid}. Tap the notification on your phone to turn it on.",
            PhoneHotspot.Status.Joining joining => $"Joining {joining.Ssid}…",
            PhoneHotspot.Status.Failed failed => failed.Reason,
            _ => "Joined. Connecting to your phone…",
        };
    }

    /// Remembers the phone's hotspot when this PC is on it.
    private void LearnHotspot(Device device)
    {
        var (id, host) = (device.Id, device.Link.Host);

        Task.Run(() =>
        {
            hotspot.Learn(id, host);
            ui.TryEnqueue(() =>
            {
                Raise(nameof(PhoneHotspotName));
                Raise(nameof(HotspotButton));
                Raise(nameof(HotspotText));
            });
        });
    }

    /// Connects to the addresses the phone gave over Bluetooth.
    private void Reach(Nearby.Answer answer)
    {
        if (link is not LanLink lan) return;

        var peer = new DeviceIdentity { DeviceId = answer.DeviceId, DeviceName = "Phone", DeviceType = DeviceType.Phone, TcpPort = answer.Port };
        foreach (var address in answer.Addresses)
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    await lan.ConnectAsync(peer, address);
                }
                catch (Exception e)
                {
                    System.Diagnostics.Debug.WriteLine($"Could not reach {address}: {e.Message}");
                }
            });
        }
    }

    private void Remove(Device device)
    {
        if (!connected.Remove(device)) return;

        media.Forget(device.Id);
        Mirror.Ended(device.Id);
        if (Call?.DeviceId == device.Id) EndCall();

        Publish();
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
                    battery.Status(device.Id),
                    media.NowPlaying(device.Id),
                    locations.Location(device.Id));
            })
            .OrderBy(d => d.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();

        var primary = Primary;
        Focused = Devices.FirstOrDefault(d => d.PairState is PairState.RequestedByPeer or PairState.Requested)
            ?? Devices.FirstOrDefault(d => d.Id == primary?.Id);
        Others = Devices.Where(d => d.Id != Focused?.Id).ToList();

        SyncStores(primary);
        SendWaiting();
    }

    /// The paired phone the panel, Messages and Photos use. Every paired phone stays connected.
    private Device? Primary => new DeviceFocus(settings.SelectedPhone).Pick(connected.Paired, d => d.Id, d => d.Name);

    /// Texts and photos come from the primary phone.
    private void SyncStores(Device? phone)
    {
        folderPhone = phone;
        if (phone is not null && ShowsPhotosInExplorer)
        {
            folder.Use(phone.Id);
            folder.Connect();
        }

        if (phone is not null)
        {
            Photos.Attach(phone.Id);
            if (messagesDevice != phone.Id || !Messages.HasPhone) Messages.Attach(phone.Id);
            messagesDevice = phone.Id;
        }
        else if (messagesDevice is string id)
        {
            Photos.Detach(id);
            Messages.Detach(id);
        }
    }

    /// Keeps loading pages until the phone folder has its most recent photos.
    private void FillPhoneFolder()
    {
        if (ShowsPhotosInExplorer && folder.IsConnected && Photos.HasPhone && Photos.HasMore && Photos.Count < PhoneFolder.Limit) Photos.LoadMore();
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

    /// Messages should open, writing to this number when one is given.
    public event Action<string?>? MessagesRequested;

    public event Action? PhotosRequested;

    /// The dialer should open, to call from the phone.
    public event Action? DialerRequested;

    public void ShowMessages(string? number = null) => MessagesRequested?.Invoke(number);

    public void ShowPhotos() => PhotosRequested?.Invoke();

    public void ShowDialer() => DialerRequested?.Invoke();

    /// Asks the phone to share its screen and opens the window that shows it.
    public void StartMirroring(string id)
    {
        if (connected[id] is not { IsPaired: true } device) return;

        Mirror.Begin(id, device.Name);
        MirrorRequested?.Invoke();
    }

    public event Action? MirrorRequested;

    /// A phone started streaming its screen, whether asked here or on the phone. Carries the decoder's source.
    public event Action<Windows.Media.Core.MediaStreamSource>? ScreenStarted;
}
