using System.Text.Json.Nodes;

namespace FlyyLink.Core;

/// Where the phone is, for finding it on a map. `Accuracy` is in metres, `Time` in milliseconds.
/// Mirrors Location.kt and Location.swift.
public sealed record PhoneLocation(double Latitude, double Longitude, double Accuracy, long Time)
{
    public static NetworkPacket Request() => new(PacketType.LocationRequest);

    public static PhoneLocation? FromPacket(NetworkPacket packet)
    {
        if (packet.Type != PacketType.Location
            || packet.GetDouble("latitude") is not (double latitude and >= -90 and <= 90)
            || packet.GetDouble("longitude") is not (double longitude and >= -180 and <= 180))
            return null;

        return new PhoneLocation(latitude, longitude, packet.GetDouble("accuracy") ?? 0, packet.GetLong("time") ?? 0);
    }

    public NetworkPacket ToPacket() => new(PacketType.Location, new JsonObject
    {
        ["latitude"] = Latitude,
        ["longitude"] = Longitude,
        ["accuracy"] = Accuracy,
        ["time"] = Time,
    });
}
