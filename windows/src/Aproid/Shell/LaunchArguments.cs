using System.Runtime.InteropServices;

namespace Aproid.Shell;

/// What Aproid was started with: files to send from Explorer, a tel: link to call, or a start at sign-in.
internal sealed record LaunchArguments(IReadOnlyList<string> Files, string? Number, bool Background)
{
    public bool IsEmpty => Files.Count == 0 && Number is null;

    public static LaunchArguments Parse(IEnumerable<string> arguments)
    {
        var files = new List<string>();
        string? number = null;
        var background = false;
        var sending = false;

        foreach (var argument in arguments)
        {
            if (argument == Startup.BackgroundArgument) background = true;
            else if (argument == Integration.SendArgument) sending = true;
            else if (argument.StartsWith("tel:", StringComparison.OrdinalIgnoreCase)) number = DigitsOf(argument);
            else if (sending && File.Exists(argument)) files.Add(argument);
        }

        return new LaunchArguments(files, number, background);
    }

    /// Splits a command line the way Windows does. It may start with the program itself, which is left out.
    public static LaunchArguments Parse(string commandLine)
    {
        var pointer = CommandLineToArgvW(commandLine, out var count);
        if (pointer == IntPtr.Zero) return new LaunchArguments([], null, false);

        try
        {
            var arguments = Enumerable.Range(0, count)
                .Select(i => Marshal.PtrToStringUni(Marshal.ReadIntPtr(pointer, i * IntPtr.Size)) ?? "")
                .Where((argument, index) => index > 0 || !argument.EndsWith(".exe", StringComparison.OrdinalIgnoreCase));

            return Parse(arguments);
        }
        finally
        {
            LocalFree(pointer);
        }
    }

    /// The digits of a tel: link, keeping + * and #.
    private static string? DigitsOf(string link)
    {
        var number = new string(Uri.UnescapeDataString(link[4..]).Where(c => char.IsAsciiDigit(c) || c is '+' or '*' or '#').ToArray());

        return number.Length > 0 ? number : null;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CommandLineToArgvW(string commandLine, out int count);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);
}
