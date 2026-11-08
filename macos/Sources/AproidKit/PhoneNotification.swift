import Foundation

/// A notification mirrored from the phone ("kdeconnect.notification").
/// `replyId` is set when the notification can be answered with text. Mirrors PhoneNotification.kt.
public struct PhoneNotification: Equatable, Sendable {
    public var id: String
    public var appName: String
    public var title: String
    public var text: String
    public var time: Int64
    public var isClearable: Bool
    public var replyId: String?
    public var silent: Bool

    public init(
        id: String,
        appName: String,
        title: String,
        text: String,
        time: Int64,
        isClearable: Bool = true,
        replyId: String? = nil,
        silent: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.title = title
        self.text = text
        self.time = time
        self.isClearable = isClearable
        self.replyId = replyId
        self.silent = silent
    }

    /// Nil for removals and malformed packets.
    public init?(packet: NetworkPacket) {
        guard packet.type == PacketType.notification, packet.bool("isCancel") != true,
              let id = packet.string("id")
        else { return nil }

        // KDE Connect sends the time as a string.
        let time = packet.string("time").flatMap { Int64($0) } ?? packet.int("time") ?? 0
        let replyId = packet.string("requestReplyId")

        self.init(
            id: id,
            appName: packet.string("appName") ?? "",
            title: packet.string("title") ?? "",
            text: packet.string("text") ?? "",
            time: time,
            isClearable: packet.bool("isClearable") ?? true,
            replyId: replyId?.isEmpty == false ? replyId : nil,
            silent: packet.bool("silent") ?? false
        )
    }

    public func toPacket() -> NetworkPacket {
        var body: [String: JSONValue] = [
            "id": .string(id),
            "appName": .string(appName),
            "title": .string(title),
            "text": .string(text),
            "ticker": .string([title, text].filter { !$0.isEmpty }.joined(separator: ": ")),
            "time": .string(String(time)),
            "isClearable": .bool(isClearable),
            "silent": .bool(silent),
        ]
        if let replyId { body["requestReplyId"] = .string(replyId) }

        return NetworkPacket(type: PacketType.notification, body: body)
    }

    public static func cancelPacket(id: String) -> NetworkPacket {
        NetworkPacket(type: PacketType.notification, body: ["id": .string(id), "isCancel": true])
    }

    /// The id of a removed notification, or nil if the packet is not a removal.
    public static func cancelledId(_ packet: NetworkPacket) -> String? {
        guard packet.type == PacketType.notification, packet.bool("isCancel") == true else { return nil }

        return packet.string("id")
    }
}

/// Packets the Mac sends back about notifications.
public enum NotificationRequests {
    public static func requestAll() -> NetworkPacket {
        NetworkPacket(type: PacketType.notificationRequest, body: ["request": true])
    }

    public static func dismiss(_ id: String) -> NetworkPacket {
        NetworkPacket(type: PacketType.notificationRequest, body: ["cancel": .string(id)])
    }

    public static func reply(to replyId: String, message: String) -> NetworkPacket {
        NetworkPacket(
            type: PacketType.notificationReply,
            body: ["requestReplyId": .string(replyId), "message": .string(message)]
        )
    }
}
