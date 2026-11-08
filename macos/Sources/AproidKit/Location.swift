import Foundation

/// Where the phone is, for finding it on the Mac's map. `accuracy` is in metres, `time` in milliseconds.
/// Mirrors Location.kt.
public struct PhoneLocation: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracy: Double
    public var time: Int64

    public init(latitude: Double, longitude: Double, accuracy: Double, time: Int64) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.time = time
    }

    public static func request() -> NetworkPacket {
        NetworkPacket(type: PacketType.locationRequest)
    }

    public init?(packet: NetworkPacket) {
        guard packet.type == PacketType.location,
              let latitude = packet.double("latitude"), (-90...90).contains(latitude),
              let longitude = packet.double("longitude"), (-180...180).contains(longitude)
        else { return nil }

        self.init(latitude: latitude, longitude: longitude, accuracy: packet.double("accuracy") ?? 0, time: packet.int("time") ?? 0)
    }

    public func toPacket() -> NetworkPacket {
        NetworkPacket(type: PacketType.location, body: [
            "latitude": .double(latitude),
            "longitude": .double(longitude),
            "accuracy": .double(accuracy),
            "time": .int(time),
        ])
    }
}
