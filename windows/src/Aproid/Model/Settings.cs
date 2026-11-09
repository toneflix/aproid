using System.Text.Json;

namespace Aproid.Model;

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
