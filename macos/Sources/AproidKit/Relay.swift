import Foundation

/// A phone's packets passed on by one computer to another that isn't connected to that phone ("flyylink.relay").
/// The computer next to the phone wraps what the phone sends, such as notifications and calls. The other computer
/// wraps its answers, such as replies and call buttons, and the first one hands them to the phone. Payloads are not
/// relayed. Mirrors Relay.kt and Relay.cs.
public enum Relay {
    /// What a computer passes on from a phone.
    public static let fromPhone: Set<String> = [PacketType.notification, PacketType.telephony]

    /// What a computer passes on to a phone.
    public static let toPhone: Set<String> = [
        PacketType.notificationRequest,
        PacketType.notificationReply,
        PacketType.notificationAction,
        PacketType.callRequest,
    ]

    public struct Message: Equatable, Sendable {
        public var phoneId: String
        public var phoneName: String
        public var packet: NetworkPacket

        public init(phoneId: String, phoneName: String, packet: NetworkPacket) {
            self.phoneId = phoneId
            self.phoneName = phoneName
            self.packet = packet
        }
    }

    public static func wrap(_ packet: NetworkPacket, phoneId: String, phoneName: String) -> NetworkPacket {
        NetworkPacket(type: PacketType.relay, body: [
            "phoneId": .string(phoneId),
            "phoneName": .string(phoneName),
            "packet": .object(["type": .string(packet.type), "body": .object(packet.body)]),
        ])
    }

    /// The wrapped packet, or nil when it isn't one that may be relayed.
    public static func message(_ packet: NetworkPacket) -> Message? {
        guard packet.type == PacketType.relay,
              let phoneId = packet.string("phoneId"), !phoneId.isEmpty,
              case .object(let inner)? = packet.body["packet"],
              let type = inner["type"]?.stringValue, fromPhone.contains(type) || toPhone.contains(type)
        else { return nil }

        var body: [String: JSONValue] = [:]
        if case .object(let wrapped)? = inner["body"] { body = wrapped }

        let name = packet.string("phoneName").flatMap { $0.isEmpty ? nil : $0 } ?? "Phone"
        return Message(phoneId: phoneId, phoneName: name, packet: NetworkPacket(type: type, body: body, id: packet.id))
    }
}
