using System.Security.Cryptography;
using System.Text;
using Aproid.Core;
using Aproid.Model;
using Microsoft.Windows.AppNotifications.Builder;

namespace Aproid.Plugins;

/// Shows phone notifications as Windows notifications. Replying, dismissing or pressing
/// one of the phone's buttons there is sent back to the phone.
internal sealed class NotificationPlugin(ToastCenter toasts, DeviceRegistry devices) : IPlugin
{
    private const string ReplyInput = "reply";
    private const string ActionPrefix = "action.";

    /// Windows shows at most five buttons on a notification.
    private const int MaxButtons = 5;

    private readonly NotificationIcons icons = new();
    private readonly Dictionary<string, string> shown = [];
    private readonly object gate = new();
    private bool enabled = true;

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.Notification };

    /// Paused from the panel: phone notifications are dropped instead of shown.
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

    /// Called after a phone notification is shown, on any thread.
    public Action? OnShown { get; set; }

    public void OnPaired(Device device) => device.Send(NotificationRequests.RequestAll());

    public void OnPacket(NetworkPacket packet, Device device)
    {
        if (PhoneNotification.CancelledId(packet) is string cancelled)
        {
            var tag = Tag(cancelled);
            lock (gate) shown.Remove(Identifier(device.Id, cancelled));
            toasts.Remove(tag, device.Id);
            return;
        }

        if (!IsEnabled || PhoneNotification.FromPacket(packet) is not PhoneNotification note) return;

        // A resend after reconnecting, or an update that changes nothing, should not pop up again.
        var summary = $"{note.Title}\n{note.Text}";
        lock (gate)
        {
            var identifier = Identifier(device.Id, note.Id);
            if (shown.TryGetValue(identifier, out var previous) && previous == summary) return;

            shown[identifier] = summary;
        }

        _ = ShowAsync(note, packet, device);
    }

    private async Task ShowAsync(PhoneNotification note, NetworkPacket packet, Device device)
    {
        // The phone sends the app icon, or the sender's photo, as the payload.
        var icon = await icons.IconAsync(packet, note.IconHash, device);
        var deviceId = device.Id;

        toasts.Show(key =>
        {
            var builder = new AppNotificationBuilder()
                .AddText(note.Title.Length == 0 ? note.AppName : note.Title)
                .AddText(note.Text)
                .SetAttributionText(note.Title.Length == 0 ? device.Name : $"{note.AppName} · {device.Name}");

            if (icon is not null) builder.SetAppLogoOverride(new Uri(icon), AppNotificationImageCrop.Circle);

            var buttons = 0;
            if (note.ReplyId is not null)
            {
                builder.AddTextBox(ReplyInput, "Message", "");
                builder.AddButton(ToastCenter.Button("Send", "reply", key).SetInputId(ReplyInput));
                buttons++;
            }

            // The phone's own buttons, such as "Mark as read".
            foreach (var title in note.ActionTitles.Take(MaxButtons - buttons - (note.IsClearable ? 1 : 0)))
            {
                builder.AddButton(ToastCenter.Button(title, ActionPrefix + title, key));
                buttons++;
            }

            if (note.IsClearable && buttons < MaxButtons) builder.AddButton(ToastCenter.Button("Dismiss on phone", "dismiss", key));

            return builder;
        }, (action, input) => Respond(action, input, deviceId, note), Tag(note.Id), deviceId, quiet: note.Silent);

        if (!note.Silent) OnShown?.Invoke();
    }

    private void Respond(string action, IDictionary<string, string> input, string deviceId, PhoneNotification note)
    {
        if (devices[deviceId] is not Device device) return;

        switch (action)
        {
            case "reply" when note.ReplyId is not null && input.TryGetValue(ReplyInput, out var text) && text.Trim().Length > 0:
                device.Send(NotificationRequests.Reply(note.ReplyId, text));
                break;
            case "dismiss":
                device.Send(NotificationRequests.Dismiss(note.Id));
                break;
            case var pressed when pressed.StartsWith(ActionPrefix, StringComparison.Ordinal):
                device.Send(NotificationRequests.Action(note.Id, pressed[ActionPrefix.Length..]));
                break;
        }
    }

    private static string Identifier(string device, string id) => $"{device}/{id}";

    /// Windows allows short tags only, so the phone's id is hashed.
    private static string Tag(string id) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(id)))[..32];
}
