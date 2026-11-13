using System.Runtime.InteropServices;

namespace Aproid.Shell;

/// The shortcuts in the jump list of FlyyLink's Start menu and pinned taskbar icon.
internal enum JumpTask
{
    Panel,
    Messages,
    Photos,
    Mirror,
    Ring,
    SendClipboard,
    SendFiles,
}

/// Fills the jump list through the shell's ICustomDestinationList. Each task starts FlyyLink with `--open <task>`,
/// which the running copy receives as a redirected launch.
internal static class JumpList
{
    public const string OpenArgument = "--open";

    private static readonly (JumpTask Task, string Title)[] Tasks =
    [
        (JumpTask.Messages, "Messages"),
        (JumpTask.Photos, "Photos"),
        (JumpTask.Mirror, "Mirror phone screen"),
        (JumpTask.Ring, "Ring phone"),
        (JumpTask.SendClipboard, "Send clipboard"),
        (JumpTask.SendFiles, "Send files"),
    ];

    public static void Register()
    {
        var exe = Environment.ProcessPath;
        if (exe is null) return;

        try
        {
            var list = (ICustomDestinationList)Create(DestinationList);
            var arrayId = typeof(IObjectArray).GUID;
            list.BeginList(out _, ref arrayId, out _);

            var tasks = (IObjectCollection)Create(EnumerableObjectCollection);
            foreach (var (task, title) in Tasks) tasks.AddObject(Link(exe, task, title));

            list.AddUserTasks((IObjectArray)tasks);
            list.CommitList();
        }
        catch (Exception e) when (e is COMException or InvalidCastException)
        {
            System.Diagnostics.Debug.WriteLine($"Jump list failed: {e.Message}");
        }
    }

    private static IShellLinkW Link(string exe, JumpTask task, string title)
    {
        var link = (IShellLinkW)Create(ShellLink);
        link.SetPath(exe);
        link.SetArguments($"{OpenArgument} {task.ToString().ToLowerInvariant()}");
        link.SetIconLocation(exe, 0);

        var key = TitleKey;
        var value = new PropVariant(title);
        try
        {
            var properties = (IPropertyStore)link;
            properties.SetValue(ref key, ref value);
            properties.Commit();
        }
        finally
        {
            PropVariantClear(ref value);
        }

        return link;
    }

    private static object Create(Guid classId) => Activator.CreateInstance(Type.GetTypeFromCLSID(classId, throwOnError: true)!)!;

    private static readonly Guid DestinationList = new("77f10cf0-3db5-4966-b520-b7c54fd35ed6");
    private static readonly Guid EnumerableObjectCollection = new("2d3468c1-36a7-43b6-ac24-d3f02fd9607a");
    private static readonly Guid ShellLink = new("00021401-0000-0000-C000-000000000046");
    private static readonly PropertyKey TitleKey = new(new Guid("F29F85E0-4FF9-1068-AB91-08002B27B3D9"), 2);

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct PropertyKey(Guid format, uint id)
    {
        public Guid Format = format;
        public uint Id = id;
    }

    /// A PROPVARIANT holding a string (VT_LPWSTR).
    [StructLayout(LayoutKind.Explicit, Size = 24)]
    private struct PropVariant
    {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public IntPtr Pointer;

        public PropVariant(string text)
        {
            Type = 31;
            Pointer = Marshal.StringToCoTaskMemUni(text);
        }
    }

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PropVariant value);

    [ComImport, Guid("6332debf-87b5-4670-90c0-5e57b408a49e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ICustomDestinationList
    {
        void SetAppID([MarshalAs(UnmanagedType.LPWStr)] string appId);
        void BeginList(out uint minSlots, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object removed);
        void AppendCategory([MarshalAs(UnmanagedType.LPWStr)] string category, IObjectArray items);
        void AppendKnownCategory(int category);
        void AddUserTasks(IObjectArray tasks);
        void CommitList();
        void GetRemovedDestinations(ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object removed);
        void DeleteList([MarshalAs(UnmanagedType.LPWStr)] string? appId);
        void AbortList();
    }

    [ComImport, Guid("92ca9dcd-5622-4bba-a805-5e9f541bd8c9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IObjectArray
    {
        void GetCount(out uint count);
        void GetAt(uint index, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object item);
    }

    [ComImport, Guid("5632b1a4-e38a-400a-928a-d4cd63230295"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IObjectCollection
    {
        // IObjectArray
        void GetCount(out uint count);
        void GetAt(uint index, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object item);

        void AddObject([MarshalAs(UnmanagedType.Interface)] object item);
        void AddFromArray(IObjectArray source);
        void RemoveObjectAt(uint index);
        void Clear();
    }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW
    {
        void GetPath([MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder file, int size, IntPtr findData, uint flags);
        void GetIDList(out IntPtr idList);
        void SetIDList(IntPtr idList);
        void GetDescription([MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder name, int size);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder directory, int size);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string directory);
        void GetArguments([MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder arguments, int size);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
        void GetHotkey(out ushort hotkey);
        void SetHotkey(ushort hotkey);
        void GetShowCmd(out int showCommand);
        void SetShowCmd(int showCommand);
        void GetIconLocation([MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder iconPath, int size, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string iconPath, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string file);
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
        void SetValue(ref PropertyKey key, ref PropVariant value);
        void Commit();
    }
}
