namespace FlyyLink.Core;

/// Makes the phone ring. Mirrors FindMyPhone.kt and FindMyPhone.swift.
public static class FindMyPhone
{
    public static NetworkPacket Request() => new(PacketType.FindMyPhone);
}
