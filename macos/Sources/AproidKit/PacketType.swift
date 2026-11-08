import Foundation

/// KDE Connect protocol version we speak.
public let protocolVersion = 8

/// UDP port used for discovery broadcasts.
public let udpPort: UInt16 = 1716

/// TCP ports KDE Connect clients try, in order.
public let tcpPortRange: ClosedRange<UInt16> = 1716...1764

/// TCP ports a sender opens for payloads such as files.
public let payloadPortRange: ClosedRange<UInt16> = 1739...1764

/// Packet types. Standard KDE Connect ones use "kdeconnect.", our extensions use "aproid.".
/// Keep in sync with android/protocol/.../PacketType.kt.
public enum PacketType {
    public static let identity = "kdeconnect.identity"
    public static let pair = "kdeconnect.pair"
    public static let ping = "kdeconnect.ping"
    public static let battery = "kdeconnect.battery"
    public static let batteryRequest = "kdeconnect.battery.request"
    public static let clipboard = "kdeconnect.clipboard"
    public static let clipboardConnect = "kdeconnect.clipboard.connect"
    public static let notification = "kdeconnect.notification"
    public static let notificationRequest = "kdeconnect.notification.request"
    public static let notificationReply = "kdeconnect.notification.reply"
    public static let notificationAction = "kdeconnect.notification.action"
    public static let shareRequest = "kdeconnect.share.request"
    public static let findMyPhone = "kdeconnect.findmyphone.request"
    public static let mpris = "kdeconnect.mpris"
    public static let mprisRequest = "kdeconnect.mpris.request"
    public static let smsMessages = "kdeconnect.sms.messages"
    public static let smsRequest = "kdeconnect.sms.request"
    public static let smsRequestConversations = "kdeconnect.sms.request_conversations"
    public static let smsRequestConversation = "kdeconnect.sms.request_conversation"
    public static let telephony = "kdeconnect.telephony"

    /// A copied picture or file, sent as the payload. Body: {"name": ..., "mimeType": ...}.
    public static let clipboardFile = "aproid.clipboard.file"

    /// Answer, decline or hang up a call, or dial a number. Body: {"action": ..., "number"?: ...}.
    public static let callRequest = "aproid.call.request"

    /// Keeps the link alive and detects a dead one. Body: {"pong": bool}.
    public static let heartbeat = "aproid.heartbeat"
}

public enum Capabilities {
    public static let mvp: Set<String> = [
        PacketType.ping,
        PacketType.battery,
        PacketType.batteryRequest,
        PacketType.clipboard,
        PacketType.clipboardConnect,
        PacketType.notification,
        PacketType.notificationRequest,
        PacketType.notificationReply,
        PacketType.notificationAction,
        PacketType.shareRequest,
        PacketType.findMyPhone,
        PacketType.mpris,
        PacketType.mprisRequest,
        PacketType.smsMessages,
        PacketType.smsRequest,
        PacketType.smsRequestConversations,
        PacketType.smsRequestConversation,
        PacketType.telephony,
        PacketType.callRequest,
        PacketType.clipboardFile,
        PacketType.heartbeat,
    ]
}
