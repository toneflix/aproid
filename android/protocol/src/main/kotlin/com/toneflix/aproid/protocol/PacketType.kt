package com.toneflix.aproid.protocol

/** KDE Connect protocol version we speak. */
const val PROTOCOL_VERSION = 8

/** UDP port used for discovery broadcasts. */
const val UDP_PORT = 1716

/** TCP ports KDE Connect clients try, in order. */
val TCP_PORT_RANGE = 1716..1764

/** TCP ports a sender opens for payloads such as files. */
val PAYLOAD_PORT_RANGE = 1739..1764

/** Packet types. Standard KDE Connect ones use "kdeconnect.", our extensions use "aproid.". */
object PacketType {
    const val IDENTITY = "kdeconnect.identity"
    const val PAIR = "kdeconnect.pair"
    const val PING = "kdeconnect.ping"
    const val BATTERY = "kdeconnect.battery"
    const val BATTERY_REQUEST = "kdeconnect.battery.request"
    const val CLIPBOARD = "kdeconnect.clipboard"
    const val CLIPBOARD_CONNECT = "kdeconnect.clipboard.connect"
    const val NOTIFICATION = "kdeconnect.notification"
    const val NOTIFICATION_REQUEST = "kdeconnect.notification.request"
    const val NOTIFICATION_REPLY = "kdeconnect.notification.reply"
    const val NOTIFICATION_ACTION = "kdeconnect.notification.action"
    const val SHARE_REQUEST = "kdeconnect.share.request"
    const val FIND_MY_PHONE = "kdeconnect.findmyphone.request"
    const val MPRIS = "kdeconnect.mpris"
    const val MPRIS_REQUEST = "kdeconnect.mpris.request"
    const val SMS_MESSAGES = "kdeconnect.sms.messages"
    const val SMS_REQUEST = "kdeconnect.sms.request"
    const val SMS_REQUEST_CONVERSATIONS = "kdeconnect.sms.request_conversations"
    const val SMS_REQUEST_CONVERSATION = "kdeconnect.sms.request_conversation"
    const val TELEPHONY = "kdeconnect.telephony"

    /** Asks the phone where it is. Body: {}. */
    const val LOCATION_REQUEST = "aproid.location.request"

    /** Where the phone is. Body: {"latitude", "longitude", "accuracy" (metres), "time" (ms)}. */
    const val LOCATION = "aproid.location"

    /** A copied picture or file, sent as the payload. Body: {"name": ..., "mimeType": ...}. */
    const val CLIPBOARD_FILE = "aproid.clipboard.file"

    /** Answer, decline or hang up a call, or dial a number. Body: {"action": ..., "number"?: ...}. */
    const val CALL_REQUEST = "aproid.call.request"

    /** Keeps the link alive and detects a dead one. Body: {"pong": bool}. */
    const val HEARTBEAT = "aproid.heartbeat"
}

/** What this MVP sends and accepts. Kept in one place so both apps advertise the same set. */
object Capabilities {
    val mvp: Set<String> = setOf(
        PacketType.PING,
        PacketType.BATTERY,
        PacketType.BATTERY_REQUEST,
        PacketType.CLIPBOARD,
        PacketType.CLIPBOARD_CONNECT,
        PacketType.NOTIFICATION,
        PacketType.NOTIFICATION_REQUEST,
        PacketType.NOTIFICATION_REPLY,
        PacketType.NOTIFICATION_ACTION,
        PacketType.SHARE_REQUEST,
        PacketType.FIND_MY_PHONE,
        PacketType.MPRIS,
        PacketType.MPRIS_REQUEST,
        PacketType.SMS_MESSAGES,
        PacketType.SMS_REQUEST,
        PacketType.SMS_REQUEST_CONVERSATIONS,
        PacketType.SMS_REQUEST_CONVERSATION,
        PacketType.TELEPHONY,
        PacketType.CALL_REQUEST,
        PacketType.CLIPBOARD_FILE,
        PacketType.LOCATION_REQUEST,
        PacketType.LOCATION,
        PacketType.HEARTBEAT,
    )
}
