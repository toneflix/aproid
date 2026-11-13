using System.Runtime.InteropServices;
using static Aproid.Shell.NativeMethods;

namespace Aproid.Shell;

/// The notification area icon, on a hidden window that also hears clipboard changes.
/// Create and use it on the UI thread, which pumps the window's messages.
internal sealed class TrayIcon : IDisposable
{
    private const uint CallbackMessage = WM_APP + 1;
    private const string ClassName = "AproidTrayWindow";

    // Held so the garbage collector does not free the callback Windows calls into.
    private readonly WndProc procedure;
    private readonly uint taskbarCreated;
    private readonly IntPtr hwnd;
    private IntPtr icon;
    private string tooltip;
    private readonly HashSet<int> hotkeys = [];
    private readonly TrayBadge badge;

    public TrayIcon(string iconPath, string tooltip)
    {
        this.tooltip = tooltip;
        procedure = Procedure;
        taskbarCreated = RegisterWindowMessage("TaskbarCreated");

        var instance = GetModuleHandle(null);
        var windowClass = new WNDCLASSEX
        {
            cbSize = (uint)Marshal.SizeOf<WNDCLASSEX>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(procedure),
            hInstance = instance,
            lpszClassName = ClassName,
        };
        RegisterClassEx(ref windowClass);
        hwnd = CreateWindowEx(0, ClassName, "FlyyLink", 0, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);

        badge = new TrayBadge(iconPath);
        icon = LoadImage(IntPtr.Zero, iconPath, IMAGE_ICON, GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE);
        Add();
        AddClipboardFormatListener(hwnd);
    }

    /// Left click on the icon.
    public event Action? Clicked;

    /// Right click on the icon.
    public event Action? MenuRequested;

    /// Something new was copied, by any app.
    public event Action? ClipboardChanged;

    /// A shortcut was pressed, with the id it was turned on with.
    public event Action<int>? HotkeyPressed;

    /// Turns shortcut `id` on or off. Returns false when another app already uses it.
    public bool UseHotkey(int id, bool on, uint modifiers, uint key)
    {
        if (hotkeys.Remove(id)) UnregisterHotKey(hwnd, id);
        if (!on) return true;

        if (!RegisterHotKey(hwnd, id, modifiers, key)) return false;

        hotkeys.Add(id);
        return true;
    }

    public string Tooltip
    {
        get => tooltip;
        set
        {
            tooltip = value;
            var data = Data(NIF_TIP);
            Shell_NotifyIcon(NIM_MODIFY, ref data);
        }
    }

    /// Shows the phone's battery as a bar on the icon, or the plain icon for null.
    public void ShowBattery(Core.BatteryStatus? battery)
    {
        IntPtr drawn;
        try
        {
            drawn = badge.Draw(GetSystemMetrics(SM_CXSMICON), battery);
        }
        catch (Exception e) when (e is ArgumentException or ExternalException or IOException)
        {
            System.Diagnostics.Debug.WriteLine($"Tray icon failed: {e.Message}");
            return;
        }

        var old = icon;
        icon = drawn;
        var data = Data(NIF_ICON);
        Shell_NotifyIcon(NIM_MODIFY, ref data);
        if (old != IntPtr.Zero) DestroyIcon(old);
    }

    /// Where the icon sits on screen, in physical pixels, if Windows can tell.
    public RECT? Bounds
    {
        get
        {
            var identifier = new NOTIFYICONIDENTIFIER { cbSize = (uint)Marshal.SizeOf<NOTIFYICONIDENTIFIER>(), hWnd = hwnd, uID = 1 };

            return Shell_NotifyIconGetRect(ref identifier, out var rect) == 0 ? rect : null;
        }
    }

    /// Shows a small menu at the pointer and returns the index of the item picked, or -1.
    /// A null label is a separator.
    public int ShowMenu(IReadOnlyList<string?> labels)
    {
        var menu = CreatePopupMenu();
        for (var i = 0; i < labels.Count; i++)
        {
            if (labels[i] is string label) AppendMenu(menu, MF_STRING, (UIntPtr)(i + 1), label);
            else AppendMenu(menu, MF_SEPARATOR, UIntPtr.Zero, null);
        }

        GetCursorPos(out var point);
        SetForegroundWindow(hwnd);
        var picked = TrackPopupMenuEx(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, point.X, point.Y, hwnd, IntPtr.Zero);
        PostMessage(hwnd, WM_NULL, IntPtr.Zero, IntPtr.Zero);
        DestroyMenu(menu);

        return picked - 1;
    }

    public void Dispose()
    {
        var data = Data(0);
        Shell_NotifyIcon(NIM_DELETE, ref data);
        RemoveClipboardFormatListener(hwnd);
        foreach (var id in hotkeys) UnregisterHotKey(hwnd, id);
        hotkeys.Clear();
        DestroyWindow(hwnd);
        if (icon != IntPtr.Zero) DestroyIcon(icon);
        icon = IntPtr.Zero;
    }

    private void Add()
    {
        var data = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP);
        Shell_NotifyIcon(NIM_ADD, ref data);
    }

    private NOTIFYICONDATA Data(uint flags) => new()
    {
        cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATA>(),
        hWnd = hwnd,
        uID = 1,
        uFlags = flags,
        uCallbackMessage = CallbackMessage,
        hIcon = icon,
        szTip = tooltip,
        szInfo = "",
        szInfoTitle = "",
    };

    private IntPtr Procedure(IntPtr window, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == CallbackMessage)
        {
            switch ((int)(lParam.ToInt64() & 0xFFFF))
            {
                case WM_LBUTTONUP:
                    Clicked?.Invoke();
                    break;
                case WM_RBUTTONUP:
                    MenuRequested?.Invoke();
                    break;
            }

            return IntPtr.Zero;
        }

        if (message == WM_HOTKEY && hotkeys.Contains((int)wParam.ToInt64()))
        {
            HotkeyPressed?.Invoke((int)wParam.ToInt64());
            return IntPtr.Zero;
        }

        if (message == WM_CLIPBOARDUPDATE)
        {
            ClipboardChanged?.Invoke();
            return IntPtr.Zero;
        }

        // Explorer restarted: put the icon back.
        if (message == taskbarCreated && taskbarCreated != 0) Add();

        return DefWindowProc(window, message, wParam, lParam);
    }
}
