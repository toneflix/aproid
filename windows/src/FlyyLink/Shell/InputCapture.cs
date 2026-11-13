using FlyyLink.Core;
using static FlyyLink.Shell.NativeMethods;

namespace FlyyLink.Shell;

/// Takes this PC's keyboard and mouse over to another computer when the pointer leaves through the edge that
/// computer sits beyond, and hands them back when it returns. Low-level hooks run on their own thread.
internal sealed class InputCapture
{
    private readonly object gate = new();
    private readonly LowLevelHook mouseProc;
    private readonly LowLevelHook keyboardProc;
    private readonly List<DateTimeOffset> escapes = [];
    private Thread? thread;
    private uint threadId;
    private string? remoteId;
    private POINT park;
    private POINT last;
    private DateTimeOffset resumedAt = DateTimeOffset.MinValue;

    public InputCapture()
    {
        mouseProc = OnMouse;
        keyboardProc = OnKeyboard;
    }

    /// The edge of this PC each paired computer sits beyond, by device id.
    public Func<IReadOnlyDictionary<string, ScreenEdge>> Edges { get; set; } = () => new Dictionary<string, ScreenEdge>();

    /// True while another computer works this PC, so its pointer doesn't cross on to a third one.
    public Func<bool> IsControlled { get; set; } = () => false;

    /// Sends to a device; false when it isn't connected.
    public Func<string, RemoteInput, bool> Send { get; set; } = (_, _) => false;

    /// The computer the keyboard and mouse now work, or null while they work this PC. Called on any thread.
    public Action<string?>? OnChange { get; set; }

    public string? RemoteId
    {
        get
        {
            lock (gate) return remoteId;
        }
    }

    public bool IsRunning => thread is not null;

    public void Start()
    {
        if (thread is not null) return;

        thread = new Thread(Run) { IsBackground = true, Name = "FlyyLink input" };
        thread.Start();
    }

    public void Stop()
    {
        ReturnHere(null);
        if (thread is null) return;

        PostThreadMessage(threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        thread = null;
    }

    /// The other computer sent the pointer back through `edge`, its own side facing this PC.
    public void Resume(string deviceId, ScreenEdge edge, double position)
    {
        if (RemoteId != deviceId) return;

        var bounds = DesktopBounds.Current();
        var (x, y) = edge.Opposite().Point(position, bounds.MinX, bounds.MinY, bounds.MaxX, bounds.MaxY, inset: 6);
        ReturnHere(new POINT { X = (int)x, Y = (int)y });
    }

    /// The other computer went away while it had the keyboard and mouse.
    public void Lost(string deviceId)
    {
        if (RemoteId == deviceId) ReturnHere(null);
    }

    private void Run()
    {
        threadId = GetCurrentThreadId();
        var module = GetModuleHandle(null);
        var mouse = SetWindowsHookEx(WH_MOUSE_LL, mouseProc, module, 0);
        var keyboard = SetWindowsHookEx(WH_KEYBOARD_LL, keyboardProc, module, 0);
        GetCursorPos(out last);

        while (GetMessage(out _, IntPtr.Zero, 0, 0) > 0)
        {
        }

        UnhookWindowsHookEx(mouse);
        UnhookWindowsHookEx(keyboard);
    }

    private IntPtr OnMouse(int code, IntPtr message, IntPtr data)
    {
        if (code < 0) return CallNextHookEx(IntPtr.Zero, code, message, data);

        var info = System.Runtime.InteropServices.Marshal.PtrToStructure<MSLLHOOKSTRUCT>(data);
        if ((info.flags & LLMHF_INJECTED) != 0) return CallNextHookEx(IntPtr.Zero, code, message, data);

        var kind = (int)message;
        if (RemoteId is not string target)
        {
            if (kind == WM_MOUSEMOVE) CrossIfAtEdge(info.pt);
            return CallNextHookEx(IntPtr.Zero, code, message, data);
        }

        RemoteInput? input = kind switch
        {
            WM_MOUSEMOVE when info.pt.X != park.X || info.pt.Y != park.Y => new RemoteInput.Move(info.pt.X - park.X, info.pt.Y - park.Y),
            WM_LBUTTONDOWN => new RemoteInput.Button(MouseButton.Left, true),
            WM_LBUTTONUP => new RemoteInput.Button(MouseButton.Left, false),
            WM_RBUTTONDOWN => new RemoteInput.Button(MouseButton.Right, true),
            WM_RBUTTONUP => new RemoteInput.Button(MouseButton.Right, false),
            WM_MBUTTONDOWN => new RemoteInput.Button(MouseButton.Middle, true),
            WM_MBUTTONUP => new RemoteInput.Button(MouseButton.Middle, false),
            WM_MOUSEWHEEL => new RemoteInput.Scroll(0, WheelPoints(info.mouseData)),
            WM_MOUSEHWHEEL => new RemoteInput.Scroll(WheelPoints(info.mouseData), 0),
            _ => null,
        };

        if (input is not null && !Send(target, input))
        {
            ReturnHere(null);
            return CallNextHookEx(IntPtr.Zero, code, message, data);
        }

        return 1;
    }

    private IntPtr OnKeyboard(int code, IntPtr message, IntPtr data)
    {
        if (code < 0 || RemoteId is not string target) return CallNextHookEx(IntPtr.Zero, code, message, data);

        var info = System.Runtime.InteropServices.Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(data);
        if ((info.flags & LLKHF_INJECTED) != 0) return CallNextHookEx(IntPtr.Zero, code, message, data);

        var kind = (int)message;
        var down = kind is WM_KEYDOWN or WM_SYSKEYDOWN;
        if (WindowsKeys.Name(info.vkCode, (info.flags & LLKHF_EXTENDED) != 0) is not string name) return 1;

        if (down && name == "Escape" && EscapedThreeTimes())
        {
            ReturnHere(null);
            return 1;
        }

        if (!Send(target, new RemoteInput.Key(name, down))) ReturnHere(null);

        return 1;
    }

    /// One notch of the wheel scrolls about 30 points.
    private static double WheelPoints(uint mouseData) => (short)(mouseData >> 16) * 30.0 / WHEEL_DELTA;

    private void CrossIfAtEdge(POINT point)
    {
        var (dx, dy) = (point.X - last.X, point.Y - last.Y);
        last = point;
        if (DateTimeOffset.Now - resumedAt < TimeSpan.FromMilliseconds(400) || IsControlled()) return;

        var bounds = DesktopBounds.Current();
        foreach (var (deviceId, edge) in Edges())
        {
            if (!edge.Reached(point.X, point.Y, bounds.MinX, bounds.MinY, bounds.MaxX, bounds.MaxY) || !Heads(edge, dx, dy)) continue;

            var position = edge.Position(point.X, point.Y, bounds.MinX, bounds.MinY, bounds.MaxX, bounds.MaxY);
            if (!Send(deviceId, new RemoteInput.Enter(edge.Opposite(), position, RemoteInput.Windows))) continue;

            lock (gate)
            {
                remoteId = deviceId;
                park = point;
            }

            OnChange?.Invoke(deviceId);
            return;
        }
    }

    private static bool Heads(ScreenEdge edge, int dx, int dy) => edge switch
    {
        ScreenEdge.Left => dx < 0,
        ScreenEdge.Right => dx > 0,
        ScreenEdge.Top => dy < 0,
        _ => dy > 0,
    };

    /// Pressing Escape three times within a second brings the keyboard and mouse back, whatever the other side does.
    private bool EscapedThreeTimes()
    {
        var now = DateTimeOffset.Now;
        escapes.RemoveAll(at => now - at > TimeSpan.FromSeconds(1));
        escapes.Add(now);

        return escapes.Count >= 3;
    }

    private void ReturnHere(POINT? point)
    {
        string? target;
        lock (gate)
        {
            target = remoteId;
            remoteId = null;
        }

        if (target is null) return;

        Send(target, new RemoteInput.Release());
        escapes.Clear();
        resumedAt = DateTimeOffset.Now;
        if (point is POINT place)
        {
            SetCursorPos(place.X, place.Y);
            last = place;
        }

        OnChange?.Invoke(null);
    }
}

/// The area every screen of this PC covers together, in physical pixels.
internal readonly record struct DesktopBounds(double MinX, double MinY, double MaxX, double MaxY)
{
    public static DesktopBounds Current()
    {
        var x = GetSystemMetrics(SM_XVIRTUALSCREEN);
        var y = GetSystemMetrics(SM_YVIRTUALSCREEN);

        return new DesktopBounds(x, y, x + GetSystemMetrics(SM_CXVIRTUALSCREEN) - 1, y + GetSystemMetrics(SM_CYVIRTUALSCREEN) - 1);
    }

    /// The main screen alone, where a fraction from the screen viewer lands.
    public static DesktopBounds Primary() => new(0, 0, GetSystemMetrics(SM_CXSCREEN) - 1, GetSystemMetrics(SM_CYSCREEN) - 1);

    public (double X, double Y) Clamp(double x, double y) => (Math.Clamp(x, MinX, MaxX), Math.Clamp(y, MinY, MaxY));
}
