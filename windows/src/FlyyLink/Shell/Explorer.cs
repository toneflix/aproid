using System.Diagnostics;

namespace FlyyLink.Shell;

/// Opens files, folders and links the way Explorer does.
internal static class Explorer
{
    public static void Open(string target)
    {
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
        }
    }

    /// Opens a received file in its app. When it has moved, opens the folder it was saved in; when no app
    /// can open it, shows it in its folder.
    public static void OpenFile(string path)
    {
        if (!File.Exists(path))
        {
            if (Path.GetDirectoryName(path) is string folder && Directory.Exists(folder)) Open(folder);
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            Reveal(path);
        }
    }

    /// Opens the file's folder with the file selected.
    public static void Reveal(string path)
    {
        try
        {
            Process.Start("explorer.exe", $"/select,\"{path}\"");
        }
        catch (System.ComponentModel.Win32Exception)
        {
        }
    }
}
