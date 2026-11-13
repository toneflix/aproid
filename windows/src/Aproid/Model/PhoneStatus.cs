using System.Text.Json;
using System.Text.Json.Serialization;

namespace Aproid.Model;

/// Each paired phone's battery and connection, saved to status.json for scripts and `FlyyLink.exe --battery`.
/// The shown phone comes first.
internal sealed record PhoneStatus(IReadOnlyList<PhoneStatus.Phone> Phones)
{
    public sealed record Phone(string Id, string Name, int? Charge, bool IsCharging, bool IsConnected);

    private static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true, DefaultIgnoreCondition = JsonIgnoreCondition.Never };

    public static PhoneStatus Empty { get; } = new([]);

    /// The same phones, none of them connected, for when FlyyLink quits.
    public PhoneStatus Disconnected() => new(Phones.Select(p => p with { IsConnected = false }).ToList());

    public bool Matches(PhoneStatus other) => Phones.SequenceEqual(other.Phones);

    public static PhoneStatus Load()
    {
        try
        {
            return JsonSerializer.Deserialize<PhoneStatus>(File.ReadAllText(AppPaths.Status), Options) ?? Empty;
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
        {
            return Empty;
        }
    }

    public void Save()
    {
        try
        {
            var temporary = AppPaths.Status + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(this, Options));
            File.Move(temporary, AppPaths.Status, overwrite: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            System.Diagnostics.Debug.WriteLine($"Could not save phone status: {e.Message}");
        }
    }
}
