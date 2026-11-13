namespace FlyyLink.Model;

public enum CallPhase
{
    Ringing,
    Dialing,
    Talking,
}

/// A call on the phone that this PC is showing. `Photo` is the caller's contact photo as base64 JPEG.
public sealed record ActiveCall(string DeviceId, string DeviceName, string Number, string? Name, string? Photo, CallPhase Phase)
{
    public DateTimeOffset? Since { get; init; }

    public bool IsMuted { get; init; }

    public string Title => Name ?? Number;

    public bool IsRinging => Phase == CallPhase.Ringing;

    /// "Incoming call · Pixel 8", "Calling from Pixel 8…" or the time on the call.
    public string Status(DateTimeOffset now) => Phase switch
    {
        CallPhase.Ringing => Name is null ? $"Incoming call · {DeviceName}" : $"{Number} · {DeviceName}",
        CallPhase.Dialing => $"Calling from {DeviceName}…",
        _ => $"{Duration(now - (Since ?? now))} · On {DeviceName}",
    };

    private static string Duration(TimeSpan time)
    {
        var total = Math.Max(0, (int)time.TotalSeconds);

        return $"{total / 60}:{total % 60:00}";
    }
}
