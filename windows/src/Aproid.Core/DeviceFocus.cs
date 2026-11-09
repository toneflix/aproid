namespace Aproid.Core;

/// Picks the device that single-device features (the main panel, messages, photos, call audio) are about
/// while several paired devices stay connected at once. Mirrors DeviceFocus.kt and DeviceFocus.swift.
public sealed class DeviceFocus(string? preferredId)
{
    /// The preferred device when it is among `devices`, otherwise the first by name, then id.
    public T? Pick<T>(IEnumerable<T> devices, Func<T, string> id, Func<T, string> name) where T : class
    {
        var all = devices.ToList();

        return all.FirstOrDefault(d => id(d) == preferredId)
            ?? all.OrderBy(name, StringComparer.Ordinal).ThenBy(id, StringComparer.Ordinal).FirstOrDefault();
    }
}
