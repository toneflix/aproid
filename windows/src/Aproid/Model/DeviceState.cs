using Aproid.Core;
using Aproid.Plugins;

namespace Aproid.Model;

/// What the panel shows for one connected device.
public sealed record DeviceState(
    string Id,
    string Name,
    DeviceType Type,
    string Host,
    PairState PairState,
    string? Code,
    BatteryStatus? Battery,
    NowPlaying? Media = null,
    PhoneLocation? Location = null)
{
    public bool IsPaired => PairState == PairState.Paired;

    public bool IsComputer => Type.IsComputer();

    private string Other => IsComputer ? "the other computer" : "your phone";

    /// We asked to pair and wait for the phone.
    public bool IsOurRequest => PairState == PairState.Requested;

    public bool IsTheirRequest => PairState == PairState.RequestedByPeer;

    public string PairingTitle => IsOurRequest ? $"Waiting for {Name}" : $"Pair with {Name}?";

    public string PairingHint => IsOurRequest
        ? $"Accept on {Other} if it shows the same code."
        : $"Check that the same code shows on {Other}. Pairing lets it send {(IsComputer ? "files, links" : "notifications, files")} and your clipboard to this PC.";

    /// The verification code as separate characters.
    public IReadOnlyList<string> CodeCharacters => (Code ?? "").Where(c => !char.IsWhiteSpace(c)).Select(c => c.ToString()).ToList();

    public int Charge => Battery?.Charge ?? 0;

    public bool IsCharging => Battery?.IsCharging ?? false;

    public bool HasBattery => Battery is not null;

    public string BatteryText => Battery is { } battery ? $"{battery.Charge}%" : "–";

    public string Subtitle => PairState switch
    {
        PairState.Paired => $"Paired · {Host}",
        PairState.Requested => IsComputer ? "Waiting for the computer…" : "Waiting for the phone…",
        PairState.RequestedByPeer => "Wants to pair",
        _ => Host,
    };
}
