using static Aproid.Shell.NativeMethods;

namespace Aproid.Shell;

/// System-wide shortcuts for the shown phone that work while another app is in front.
internal sealed class GlobalShortcuts
{
    public sealed record Shortcut(JumpTask Task, uint Modifiers, char Key, string Name, string Title);

    public static readonly IReadOnlyList<Shortcut> All =
    [
        new(JumpTask.Panel, MOD_WIN | MOD_SHIFT, 'A', "Win+Shift+A", "Open Aproid"),
        new(JumpTask.SendClipboard, MOD_CONTROL | MOD_ALT, 'C', "Ctrl+Alt+C", "Send clipboard"),
        new(JumpTask.SendFiles, MOD_CONTROL | MOD_ALT, 'F', "Ctrl+Alt+F", "Send files"),
        new(JumpTask.Mirror, MOD_CONTROL | MOD_ALT, 'M', "Ctrl+Alt+M", "Mirror phone"),
        new(JumpTask.Ring, MOD_CONTROL | MOD_ALT, 'R', "Ctrl+Alt+R", "Ring phone"),
    ];

    private readonly TrayIcon tray;

    public GlobalShortcuts(TrayIcon tray)
    {
        this.tray = tray;
        tray.HotkeyPressed += id =>
        {
            if (id >= 0 && id < All.Count) Pressed?.Invoke(All[id].Task);
        };
    }

    /// One of the shortcuts was pressed.
    public event Action<JumpTask>? Pressed;

    /// Turns the shortcuts on or off. Returns the ones another app already uses.
    public IReadOnlyList<Shortcut> Use(bool on)
    {
        var taken = new List<Shortcut>();
        for (var id = 0; id < All.Count; id++)
        {
            var shortcut = All[id];
            if (!tray.UseHotkey(id, on, shortcut.Modifiers | MOD_NOREPEAT, shortcut.Key)) taken.Add(shortcut);
        }

        return taken;
    }
}
