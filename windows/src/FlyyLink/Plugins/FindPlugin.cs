using FlyyLink.Core;
using Microsoft.Windows.AppNotifications.Builder;

namespace FlyyLink.Plugins;

/// Rings this PC when a paired device asks to find it ("kdeconnect.findmyphone.request"), until someone answers the alarm.
internal sealed class FindPlugin(ToastCenter toasts) : IPlugin
{
    private const string Tag = "find";

    public IReadOnlySet<string> Incoming { get; } = new HashSet<string> { PacketType.FindMyPhone };

    public void OnPacket(NetworkPacket packet, Device device) => toasts.Show(
        key => new AppNotificationBuilder()
            .AddText("Here I am")
            .AddText($"{device.Name} is looking for this PC.")
            .SetScenario(AppNotificationScenario.Alarm)
            .SetAudioUri(new Uri("ms-winsoundevent:Notification.Looping.Alarm"))
            .AddButton(ToastCenter.Button("Found it", "found", key)),
        tag: Tag,
        group: device.Id);
}
