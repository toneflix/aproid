using System.Text.Json;

namespace Aproid.Model;

/// How the panel switches between several paired phones.
public enum PhoneSwitcherStyle
{
    /// The next phone's card peeks at the edge; clicking it moves on, round and round.
    Carousel,

    /// A menu on the phone's name.
    Menu,
}

/// The user's choices and this computer's device id, kept in settings.json.
internal sealed class Settings
{
    private readonly string path;
    private readonly Values values;

    private sealed class Values
    {
        public string? DeviceId { get; set; }
        public bool MirrorsNotifications { get; set; } = true;
        public string? SelectedPhone { get; set; }
        public PhoneSwitcherStyle SwitcherStyle { get; set; } = PhoneSwitcherStyle.Carousel;
        public Dictionary<string, string> PhoneHotspots { get; set; } = new();
        public bool UsesShortcuts { get; set; } = true;
        public bool ShowsPhotosInExplorer { get; set; } = true;
        public bool MirrorMuted { get; set; }
        public bool SharesNotifications { get; set; } = true;
    }

    public Settings(string path)
    {
        this.path = path;

        try
        {
            values = JsonSerializer.Deserialize<Values>(File.ReadAllText(path)) ?? new Values();
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
        {
            values = new Values();
        }
    }

    /// Made once, on first launch.
    public string DeviceId
    {
        get
        {
            if (values.DeviceId is string id) return id;

            values.DeviceId = Core.DeviceIdentity.NewDeviceId();
            Save();

            return values.DeviceId;
        }
    }

    public bool MirrorsNotifications
    {
        get => values.MirrorsNotifications;
        set
        {
            values.MirrorsNotifications = value;
            Save();
        }
    }

    /// The phone the user picked when several are paired.
    public string? SelectedPhone
    {
        get => values.SelectedPhone;
        set
        {
            values.SelectedPhone = value;
            Save();
        }
    }

    public PhoneSwitcherStyle SwitcherStyle
    {
        get => values.SwitcherStyle;
        set
        {
            values.SwitcherStyle = value;
            Save();
        }
    }

    /// Whether the system-wide keyboard shortcuts are on.
    public bool UsesShortcuts
    {
        get => values.UsesShortcuts;
        set
        {
            values.UsesShortcuts = value;
            Save();
        }
    }

    /// Whether the phone's photos show as a folder in Explorer.
    public bool ShowsPhotosInExplorer
    {
        get => values.ShowsPhotosInExplorer;
        set
        {
            values.ShowsPhotosInExplorer = value;
            Save();
        }
    }

    /// Whether the phone's sound stays off while mirroring.
    public bool MirrorMuted
    {
        get => values.MirrorMuted;
        set
        {
            values.MirrorMuted = value;
            Save();
        }
    }

    /// Whether this PC's notifications go to paired computers.
    public bool SharesNotifications
    {
        get => values.SharesNotifications;
        set
        {
            values.SharesNotifications = value;
            Save();
        }
    }

    /// The hotspot name of each phone, by device id.
    public IReadOnlyDictionary<string, string> PhoneHotspots => values.PhoneHotspots;

    public void RememberHotspot(string deviceId, string ssid)
    {
        values.PhoneHotspots[deviceId] = ssid;
        Save();
    }

    private void Save()
    {
        try
        {
            File.WriteAllText(path, JsonSerializer.Serialize(values));
        }
        catch (IOException)
        {
        }
    }
}
