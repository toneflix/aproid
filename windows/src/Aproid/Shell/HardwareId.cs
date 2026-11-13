using Microsoft.Win32;

namespace Aproid.Shell;

/// The ID Windows gives this installation, which stays the same when FlyyLink is reinstalled.
internal static class HardwareId
{
    public static string Read()
    {
        using var key = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64).OpenSubKey(@"SOFTWARE\Microsoft\Cryptography");

        return key?.GetValue("MachineGuid") as string ?? Environment.MachineName;
    }
}
