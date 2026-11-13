import Foundation

/// What a "kdeconnect.telephony" packet reports about a call. Mirrors Call.kt.
public enum CallEvent: String, Sendable {
    case ringing
    case talking
    case missed = "missedCall"
}

/// Calls: the phone reports them with "kdeconnect.telephony", and the Mac controls them with "flyylink.call.request".
public enum Call {
    public enum Action: String, Sendable {
        case answer
        case decline
        case hangUp
        case mute
        case unmute
        case dial
    }

    public struct Request: Equatable, Sendable {
        public var action: Action
        public var number: String?

        public init(_ action: Action, number: String? = nil) {
            self.action = action
            self.number = number
        }
    }

    /// `photo` is the caller's contact photo as base64 JPEG. `ended` means the call is over.
    public struct State: Equatable, Sendable {
        public var event: CallEvent
        public var number: String
        public var contactName: String?
        public var photo: String?
        public var ended: Bool

        public init(event: CallEvent, number: String, contactName: String? = nil, photo: String? = nil, ended: Bool = false) {
            self.event = event
            self.number = number
            self.contactName = contactName
            self.photo = photo
            self.ended = ended
        }
    }

    public static func event(_ event: CallEvent, number: String, contactName: String? = nil, photo: String? = nil) -> NetworkPacket {
        var body: [String: JSONValue] = ["event": .string(event.rawValue), "phoneNumber": .string(number)]
        if let contactName { body["contactName"] = .string(contactName) }
        if let photo { body["phoneThumbnail"] = .string(photo) }

        return NetworkPacket(type: PacketType.telephony, body: body)
    }

    public static func ended(number: String) -> NetworkPacket {
        NetworkPacket(
            type: PacketType.telephony,
            body: ["event": .string(CallEvent.ringing.rawValue), "phoneNumber": .string(number), "isCancel": true]
        )
    }

    public static func state(_ packet: NetworkPacket) -> State? {
        guard packet.type == PacketType.telephony,
              let event = packet.string("event").flatMap(CallEvent.init(rawValue:))
        else { return nil }

        return State(
            event: event,
            number: packet.string("phoneNumber") ?? "",
            contactName: packet.string("contactName").flatMap { $0.isEmpty ? nil : $0 },
            photo: packet.string("phoneThumbnail").flatMap { $0.isEmpty ? nil : $0 },
            ended: packet.bool("isCancel") == true
        )
    }

    public static func answer() -> NetworkPacket { packet(Request(.answer)) }

    public static func decline() -> NetworkPacket { packet(Request(.decline)) }

    public static func hangUp() -> NetworkPacket { packet(Request(.hangUp)) }

    public static func mute(_ muted: Bool) -> NetworkPacket { packet(Request(muted ? .mute : .unmute)) }

    public static func dial(_ number: String) -> NetworkPacket { packet(Request(.dial, number: number)) }

    public static func packet(_ request: Request) -> NetworkPacket {
        var body: [String: JSONValue] = ["action": .string(request.action.rawValue)]
        if let number = request.number { body["number"] = .string(number) }

        return NetworkPacket(type: PacketType.callRequest, body: body)
    }

    public static func request(_ packet: NetworkPacket) -> Request? {
        guard packet.type == PacketType.callRequest,
              let action = packet.string("action").flatMap(Action.init(rawValue:))
        else { return nil }

        let number = packet.string("number").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        if action == .dial && number == nil { return nil }

        return Request(action, number: number)
    }
}
