import Foundation

/// Asks the phone to ring until someone finds it ("kdeconnect.findmyphone.request"). Mirrors FindMyPhone.kt.
public enum FindMyPhone {
    public static func request() -> NetworkPacket {
        NetworkPacket(type: PacketType.findMyPhone)
    }
}
