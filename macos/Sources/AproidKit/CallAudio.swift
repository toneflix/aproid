import Foundation

/// Call audio on the Mac. Android doesn't let apps carry call audio, so the Mac joins the phone as a
/// Bluetooth hands-free device instead. These packets pair the two and report how the link stands. Mirrors CallAudio.kt.
public enum CallAudio {
    public enum Action: String, Sendable {
        case status
        case pair
    }

    /// `address` is the Mac's Bluetooth address, as "AA:BB:CC:DD:EE:FF".
    public struct Request: Equatable, Sendable {
        public var action: Action
        public var address: String
        public var name: String?

        public init(_ action: Action, address: String, name: String? = nil) {
            self.action = action
            self.address = address
            self.name = name
        }
    }

    /// `name` is the phone's Bluetooth name. `allowed` is false until the user lets Aproid use Bluetooth.
    public struct Status: Equatable, Sendable {
        public var bluetoothOn: Bool
        public var allowed: Bool
        public var paired: Bool
        public var connected: Bool
        public var name: String?

        public init(bluetoothOn: Bool, allowed: Bool, paired: Bool, connected: Bool, name: String? = nil) {
            self.bluetoothOn = bluetoothOn
            self.allowed = allowed
            self.paired = paired
            self.connected = connected
            self.name = name
        }
    }

    public static func request(_ request: Request) -> NetworkPacket {
        var body: [String: JSONValue] = ["action": .string(request.action.rawValue), "address": .string(request.address)]
        if let name = request.name { body["name"] = .string(name) }

        return NetworkPacket(type: PacketType.callAudioRequest, body: body)
    }

    public static func request(_ packet: NetworkPacket) -> Request? {
        guard packet.type == PacketType.callAudioRequest,
              let action = packet.string("action").flatMap(Action.init(rawValue:)),
              let address = normalizeAddress(packet.string("address"))
        else { return nil }

        let name = packet.string("name").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }

        return Request(action, address: address, name: name)
    }

    public static func status(_ status: Status) -> NetworkPacket {
        var body: [String: JSONValue] = [
            "bluetoothOn": .bool(status.bluetoothOn),
            "allowed": .bool(status.allowed),
            "paired": .bool(status.paired),
            "connected": .bool(status.connected),
        ]
        if let name = status.name { body["name"] = .string(name) }

        return NetworkPacket(type: PacketType.callAudio, body: body)
    }

    public static func status(_ packet: NetworkPacket) -> Status? {
        guard packet.type == PacketType.callAudio else { return nil }

        return Status(
            bluetoothOn: packet.bool("bluetoothOn") == true,
            allowed: packet.bool("allowed") == true,
            paired: packet.bool("paired") == true,
            connected: packet.bool("connected") == true,
            name: packet.string("name").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        )
    }

    /// Turns "aa-bb-cc-dd-ee-ff", "aabbccddeeff" or "AA:BB:CC:DD:EE:FF" into the last form, or nil if it isn't an address.
    public static func normalizeAddress(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let hex = raw.filter { $0.isLetter || $0.isNumber }.uppercased()
        guard hex.count == 12, hex.allSatisfy({ $0.isHexDigit }) else { return nil }

        var pairs: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            pairs.append(String(hex[index..<next]))
            index = next
        }

        return pairs.joined(separator: ":")
    }
}
