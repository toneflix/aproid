import Foundation

/// The phone's battery ("kdeconnect.battery"). Mirrors Battery.kt.
public struct BatteryStatus: Equatable, Sendable {
    public var charge: Int
    public var isCharging: Bool
    public var isLow: Bool

    /// At or below this level, and not charging, the battery counts as low.
    public static let lowLevel = 15

    private static let thresholdNone: Int64 = 0
    private static let thresholdLow: Int64 = 1

    public init(charge: Int, isCharging: Bool, isLow: Bool = false) {
        self.charge = charge
        self.isCharging = isCharging
        self.isLow = isLow
    }

    public static func of(charge: Int, isCharging: Bool) -> BatteryStatus {
        BatteryStatus(charge: charge, isCharging: isCharging, isLow: !isCharging && charge <= lowLevel)
    }

    public init?(packet: NetworkPacket) {
        guard packet.type == PacketType.battery, let charge = packet.int("currentCharge") else { return nil }

        self.init(
            charge: Int(charge),
            isCharging: packet.bool("isCharging") ?? false,
            isLow: packet.int("thresholdEvent") == Self.thresholdLow
        )
    }

    public func toPacket() -> NetworkPacket {
        NetworkPacket(type: PacketType.battery, body: [
            "currentCharge": .int(Int64(charge)),
            "isCharging": .bool(isCharging),
            "thresholdEvent": .int(isLow ? Self.thresholdLow : Self.thresholdNone),
        ])
    }

    public static func request() -> NetworkPacket {
        NetworkPacket(type: PacketType.batteryRequest, body: ["request": .bool(true)])
    }
}
