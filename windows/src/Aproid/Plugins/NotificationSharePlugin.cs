using Aproid.Core;
using Aproid.Model;
using Windows.UI.Notifications;
using Windows.UI.Notifications.Management;

namespace Aproid.Plugins;

/// Sends this PC's notifications to paired computers ("kdeconnect.notification"), and removes one here when it is
/// dismissed there. Windows only lets apps with package identity read notifications, so on an unpackaged install
/// `IsAvailable` stays false.
internal sealed class NotificationSharePlugin(DeviceRegistry devices) : IPlugin
{
    private const string IdPrefix = "windows.";
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(3);

    private readonly Dictionary<string, PhoneNotification> current = [];
    private readonly object gate = new();
    private UserNotificationListener? listener;
    private bool enabled = true;

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.NotificationRequest };

    public bool IsAvailable => listener is not null;

    /// Turned off from the settings menu: nothing more is sent.
    public bool IsEnabled
    {
        get
        {
            lock (gate) return enabled;
        }
        set
        {
            lock (gate) enabled = value;
        }
    }

    /// Asks Windows for access. Call once, on the UI thread.
    public async Task StartAsync()
    {
        try
        {
            var candidate = UserNotificationListener.Current;
            if (await candidate.RequestAccessAsync() != UserNotificationListenerAccessStatus.Allowed) return;

            listener = candidate;
        }
        catch (Exception e)
        {
            System.Diagnostics.Debug.WriteLine($"Notification access unavailable: {e.Message}");
            return;
        }

        _ = Task.Run(PollAsync);
    }

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (packet.GetBool("request") == true)
        {
            List<PhoneNotification> all;
            lock (gate) all = [.. current.Values];

            if (IsEnabled && device.Link.Identity.DeviceType.IsComputer()) all.ForEach(note => device.Send(note.ToPacket()));
        }

        if (packet.GetString("cancel") is string id && id.StartsWith(IdPrefix, StringComparison.Ordinal) && uint.TryParse(id[IdPrefix.Length..], out var number))
        {
            try
            {
                listener?.RemoveNotification(number);
            }
            catch (Exception e)
            {
                System.Diagnostics.Debug.WriteLine($"Could not remove notification {number}: {e.Message}");
            }
        }
    }

    /// Windows gives unpackaged apps no change event, so compare what is showing every few seconds.
    private async Task PollAsync()
    {
        while (listener is not null)
        {
            try
            {
                var showing = (await listener.GetNotificationsAsync(NotificationKinds.Toast)).Select(Read).OfType<PhoneNotification>().ToList();
                Update(showing);
            }
            catch (Exception e)
            {
                System.Diagnostics.Debug.WriteLine($"Reading notifications failed: {e.Message}");
            }

            await Task.Delay(PollInterval);
        }
    }

    private void Update(IReadOnlyList<PhoneNotification> showing)
    {
        List<PhoneNotification> added;
        List<string> removed;
        lock (gate)
        {
            added = showing.Where(note => !current.ContainsKey(note.Id)).ToList();
            removed = current.Keys.Where(id => showing.All(note => note.Id != id)).ToList();

            current.Clear();
            foreach (var note in showing) current[note.Id] = note;
        }

        if (!IsEnabled || (added.Count == 0 && removed.Count == 0)) return;

        foreach (var device in devices.Paired.Where(d => d.Link.Identity.DeviceType.IsComputer()))
        {
            added.ForEach(note => device.Send(note.ToPacket()));
            removed.ForEach(id => device.Send(PhoneNotification.CancelPacket(id)));
        }
    }

    /// Our own toasts already came from a phone, so they stay here.
    private static PhoneNotification? Read(UserNotification notification)
    {
        string appName;
        try
        {
            appName = notification.AppInfo.DisplayInfo.DisplayName;
        }
        catch (Exception)
        {
            appName = "Windows";
        }

        if (appName == "FlyyLink") return null;

        var texts = notification.Notification.Visual.GetBinding(KnownNotificationBindings.ToastGeneric)?.GetTextElements().Select(t => t.Text).ToList() ?? [];
        if (texts.Count == 0) return null;

        return new PhoneNotification(
            $"{IdPrefix}{notification.Id}",
            appName,
            texts[0],
            string.Join("\n", texts.Skip(1)),
            notification.CreationTime.ToUnixTimeMilliseconds());
    }
}
