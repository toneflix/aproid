import Foundation

/// A phone number or email a message went to or came from. `name` is the phone's contact name, if any.
public struct SmsAddress: Equatable, Hashable, Sendable {
    public var address: String
    public var name: String?

    public init(_ address: String, name: String? = nil) {
        self.address = address
        self.name = name
    }
}

/// A picture or file in an MMS. `thumbnail` is a small base64 JPEG.
public struct SmsAttachment: Equatable, Sendable {
    public var partId: Int64
    public var mimeType: String
    public var uniqueId: String
    public var thumbnail: String?

    public init(partId: Int64, mimeType: String, uniqueId: String, thumbnail: String? = nil) {
        self.partId = partId
        self.mimeType = mimeType
        self.uniqueId = uniqueId
        self.thumbnail = thumbnail
    }
}

/// One text or MMS, in the shape of KDE Connect's "kdeconnect.sms.messages". Mirrors Sms.kt.
public struct SmsMessage: Equatable, Identifiable, Sendable {
    public static let typeInbox: Int64 = 1
    public static let typeSent: Int64 = 2

    public var id: Int64
    public var threadId: Int64
    public var body: String
    public var addresses: [SmsAddress]
    public var date: Int64
    public var isIncoming: Bool
    public var isRead: Bool
    public var subscriptionId: Int64?
    public var attachments: [SmsAttachment]

    public init(
        id: Int64,
        threadId: Int64,
        body: String,
        addresses: [SmsAddress],
        date: Int64,
        isIncoming: Bool,
        isRead: Bool = true,
        subscriptionId: Int64? = nil,
        attachments: [SmsAttachment] = []
    ) {
        self.id = id
        self.threadId = threadId
        self.body = body
        self.addresses = addresses
        self.date = date
        self.isIncoming = isIncoming
        self.isRead = isRead
        self.subscriptionId = subscriptionId
        self.attachments = attachments
    }

    public init?(json: [String: JSONValue]) {
        guard let id = json.number("_id"), let threadId = json.number("thread_id") else { return nil }

        let addresses = (json["addresses"]?.arrayValue ?? []).compactMap { item -> SmsAddress? in
            guard let object = item.objectValue, let address = object["address"]?.stringValue else { return nil }
            return SmsAddress(address, name: object["name"]?.stringValue)
        }
        let attachments = (json["attachments"]?.arrayValue ?? []).compactMap { item -> SmsAttachment? in
            guard let part = item.objectValue, let partId = part.number("part_id") else { return nil }
            return SmsAttachment(
                partId: partId,
                mimeType: part["mime_type"]?.stringValue ?? "",
                uniqueId: part["unique_identifier"]?.stringValue ?? "",
                thumbnail: part["encoded_thumbnail"]?.stringValue
            )
        }

        self.init(
            id: id,
            threadId: threadId,
            body: json["body"]?.stringValue ?? "",
            addresses: addresses,
            date: json.number("date") ?? 0,
            isIncoming: json.number("type") != Self.typeSent,
            isRead: json.number("read").map { $0 != 0 } ?? json["read"]?.boolValue ?? true,
            subscriptionId: json.number("sub_id"),
            attachments: attachments
        )
    }

    public func toJSON() -> JSONValue {
        var json: [String: JSONValue] = [
            "_id": .int(id),
            "thread_id": .int(threadId),
            "body": .string(body),
            "date": .int(date),
            "type": .int(isIncoming ? Self.typeInbox : Self.typeSent),
            "read": .int(isRead ? 1 : 0),
            "event": .int(addresses.count > 1 ? 2 : 1),
            "addresses": .array(addresses.map { address in
                var item: [String: JSONValue] = ["address": .string(address.address)]
                if let name = address.name { item["name"] = .string(name) }
                return .object(item)
            }),
        ]
        if let subscriptionId { json["sub_id"] = .int(subscriptionId) }
        if !attachments.isEmpty {
            json["attachments"] = .array(attachments.map { attachment in
                var item: [String: JSONValue] = [
                    "part_id": .int(attachment.partId),
                    "mime_type": .string(attachment.mimeType),
                    "unique_identifier": .string(attachment.uniqueId),
                ]
                if let thumbnail = attachment.thumbnail { item["encoded_thumbnail"] = .string(thumbnail) }
                return .object(item)
            })
        }

        return .object(json)
    }
}

/// The SMS packets: message lists from the phone, and what the Mac asks for.
public enum Sms {
    public struct ConversationRequest: Equatable, Sendable {
        public var threadId: Int64
        public var before: Int64?
        public var count: Int64?
    }

    public struct SendRequest: Equatable, Sendable {
        public var addresses: [String]
        public var body: String
        public var subscriptionId: Int64?
    }

    public static func messagesPacket(_ messages: [SmsMessage]) -> NetworkPacket {
        NetworkPacket(type: PacketType.smsMessages, body: ["version": 2, "messages": .array(messages.map { $0.toJSON() })])
    }

    public static func messages(_ packet: NetworkPacket) -> [SmsMessage]? {
        guard packet.type == PacketType.smsMessages else { return nil }

        return (packet.body["messages"]?.arrayValue ?? []).compactMap { $0.objectValue.flatMap(SmsMessage.init(json:)) }
    }

    /// Asks for the newest message of every conversation.
    public static func requestConversations() -> NetworkPacket {
        NetworkPacket(type: PacketType.smsRequestConversations, body: [:])
    }

    /// Asks for up to `count` messages of one conversation, older than `before` when set.
    public static func requestConversation(_ threadId: Int64, before: Int64? = nil, count: Int64 = 50) -> NetworkPacket {
        var body: [String: JSONValue] = ["threadID": .int(threadId), "numberToRequest": .int(count)]
        if let before { body["rangeStartTimestamp"] = .int(before) }

        return NetworkPacket(type: PacketType.smsRequestConversation, body: body)
    }

    public static func conversationRequest(_ packet: NetworkPacket) -> ConversationRequest? {
        guard packet.type == PacketType.smsRequestConversation, let threadId = packet.int("threadID") else { return nil }

        let before = packet.int("rangeStartTimestamp").flatMap { $0 > 0 ? $0 : nil }
        return ConversationRequest(threadId: threadId, before: before, count: packet.int("numberToRequest"))
    }

    public static func send(to addresses: [String], body: String, subscriptionId: Int64? = nil) -> NetworkPacket {
        var packetBody: [String: JSONValue] = [
            "version": 2,
            "messageBody": .string(body),
            "addresses": .array(addresses.map { .object(["address": .string($0)]) }),
        ]
        if let subscriptionId { packetBody["subID"] = .int(subscriptionId) }

        return NetworkPacket(type: PacketType.smsRequest, body: packetBody)
    }

    public static func sendRequest(_ packet: NetworkPacket) -> SendRequest? {
        guard packet.type == PacketType.smsRequest, let body = packet.string("messageBody") else { return nil }

        // Version 1 sent a single "phoneNumber".
        let addresses = packet.body["addresses"]?.arrayValue?.compactMap { $0.objectValue?["address"]?.stringValue }
            ?? [packet.string("phoneNumber")].compactMap { $0 }
        guard !addresses.isEmpty else { return nil }

        return SendRequest(addresses: addresses, body: body, subscriptionId: packet.int("subID"))
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    /// A number that may arrive as a string, as some KDE Connect versions send ids.
    func number(_ key: String) -> Int64? {
        self[key]?.intValue ?? self[key]?.stringValue.flatMap { Int64($0) }
    }
}
