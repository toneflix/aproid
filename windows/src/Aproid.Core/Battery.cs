using System.Text.Json.Nodes;

namespace Aproid.Core;

/// The phone's battery ("kdeconnect.battery"). Mirrors Battery.kt and Battery.swift.
public sealed record BatteryStatus(int Charge, bool IsCharging, bool IsLow = false)
{
    /// At or below this level, and not charging, the battery counts as low.
    public const int LowLevel = 15;

    private const long ThresholdNone = 0;
    private const long ThresholdLow = 1;

    public static BatteryStatus Of(int charge, bool isCharging) => new(charge, isCharging, !isCharging && charge <= LowLevel);

    public static BatteryStatus? FromPacket(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Battery || packet.GetLong("currentCharge") is not long charge) return null;

        return new BatteryStatus((int)charge, packet.GetBool("isCharging") ?? false, packet.GetLong("thresholdEvent") == ThresholdLow);
    }

    public NetworkPacket ToPacket() => new(PacketType.Battery, new JsonObject
    {
        ["currentCharge"] = Charge,
        ["isCharging"] = IsCharging,
        ["thresholdEvent"] = IsLow ? ThresholdLow : ThresholdNone,
    });

    public static NetworkPacket Request() => new(PacketType.BatteryRequest, new JsonObject { ["request"] = true });
}
