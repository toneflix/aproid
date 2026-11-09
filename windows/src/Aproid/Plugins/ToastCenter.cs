using System.Collections.Concurrent;
using Aproid.Model;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace Aproid.Plugins;

/// Shows Windows notifications and routes clicks, buttons and typed replies back to whoever showed them.
internal sealed class ToastCenter
{
    /// Called with the button's action ("open" for a click on the body) and anything typed in the notification.
    public delegate void ActionHandler(string action, IDictionary<string, string> input);

    private const string KeyArgument = "k";
    private const string ActionArgument = "action";
    private const int MaxHandlers = 500;

    private readonly AppNotificationManager manager = AppNotificationManager.Default;
    private readonly ConcurrentDictionary<string, ActionHandler> handlers = new();
    private readonly ConcurrentQueue<string> order = new();

    public ToastCenter()
    {
        try
        {
            manager.NotificationInvoked += Invoked;
            manager.Register("Aproid", new Uri(AppPaths.AppIcon));
            IsAvailable = true;
        }
        catch (Exception e)
        {
            System.Diagnostics.Debug.WriteLine($"Notifications unavailable: {e.Message}");
        }
    }

    public bool IsAvailable { get; }

    /// A button that reports `action` to the notification's handler.
    public static AppNotificationButton Button(string label, string action, string key) =>
        new AppNotificationButton(label).AddArgument(KeyArgument, key).AddArgument(ActionArgument, action);

    /// Builds and shows a notification. `build` gets the key that buttons made with `Button` must carry.
    /// `quiet` puts it straight in the notification centre without a banner or sound.
    public void Show(Func<string, AppNotificationBuilder> build, ActionHandler? onAction = null, string? tag = null, string? group = null, bool quiet = false)
    {
        if (!IsAvailable) return;

        var key = Guid.NewGuid().ToString("N")[..12];
        var builder = build(key).AddArgument(KeyArgument, key).AddArgument(ActionArgument, "open");
        if (quiet) builder.MuteAudio();

        var notification = builder.BuildNotification();
        if (tag is not null) notification.Tag = tag;
        if (group is not null) notification.Group = group;
        notification.SuppressDisplay = quiet;

        if (onAction is not null) Remember(key, onAction);

        try
        {
            manager.Show(notification);
        }
        catch (Exception e)
        {
            System.Diagnostics.Debug.WriteLine($"Notification failed: {e.Message}");
        }
    }

    public void Remove(string tag, string group)
    {
        if (IsAvailable) _ = manager.RemoveByTagAndGroupAsync(tag, group);
    }

    public void Unregister()
    {
        if (IsAvailable) manager.Unregister();
    }

    private void Remember(string key, ActionHandler handler)
    {
        handlers[key] = handler;
        order.Enqueue(key);

        while (order.Count > MaxHandlers && order.TryDequeue(out var old)) handlers.TryRemove(old, out _);
    }

    private void Invoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
    {
        if (!args.Arguments.TryGetValue(KeyArgument, out var key) || !handlers.TryGetValue(key, out var handler)) return;

        handler(args.Arguments.TryGetValue(ActionArgument, out var action) ? action : "open", args.UserInput);
    }
}
