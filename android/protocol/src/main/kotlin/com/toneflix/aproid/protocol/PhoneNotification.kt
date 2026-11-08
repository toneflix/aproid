package com.toneflix.aproid.protocol

/**
 * A notification mirrored from the phone ("kdeconnect.notification").
 * [replyId] is set when the notification can be answered with text.
 */
data class PhoneNotification(
    val id: String,
    val appName: String,
    val title: String,
    val text: String,
    val time: Long,
    val isClearable: Boolean = true,
    val replyId: String? = null,
    val silent: Boolean = false,
) {
    fun toPacket(): NetworkPacket = NetworkPacket(
        type = PacketType.NOTIFICATION,
        body = NetworkPacket.body(
            "id" to id,
            "appName" to appName,
            "title" to title,
            "text" to text,
            "ticker" to listOf(title, text).filter { it.isNotEmpty() }.joinToString(": "),
            "time" to time.toString(),
            "isClearable" to isClearable,
            "requestReplyId" to replyId,
            "silent" to silent,
        ),
    )

    companion object {
        fun cancelPacket(id: String): NetworkPacket = NetworkPacket(
            type = PacketType.NOTIFICATION,
            body = NetworkPacket.body("id" to id, "isCancel" to true),
        )

        /** The id of a removed notification, or null if the packet is not a removal. */
        fun cancelledId(packet: NetworkPacket): String? {
            if (packet.type != PacketType.NOTIFICATION || packet.bool("isCancel") != true) return null

            return packet.string("id")
        }

        /** Null for removals and malformed packets. */
        fun fromPacket(packet: NetworkPacket): PhoneNotification? {
            if (packet.type != PacketType.NOTIFICATION || packet.bool("isCancel") == true) return null

            val id = packet.string("id") ?: return null
            // KDE Connect sends the time as a string.
            val time = packet.string("time")?.toLongOrNull() ?: packet.long("time") ?: 0L

            return PhoneNotification(
                id = id,
                appName = packet.string("appName") ?: "",
                title = packet.string("title") ?: "",
                text = packet.string("text") ?: "",
                time = time,
                isClearable = packet.bool("isClearable") ?: true,
                replyId = packet.string("requestReplyId")?.takeIf { it.isNotEmpty() },
                silent = packet.bool("silent") ?: false,
            )
        }
    }
}

/** Packets the Mac sends back about notifications. */
object NotificationRequests {
    fun requestAll(): NetworkPacket =
        NetworkPacket(PacketType.NOTIFICATION_REQUEST, NetworkPacket.body("request" to true))

    fun dismiss(id: String): NetworkPacket =
        NetworkPacket(PacketType.NOTIFICATION_REQUEST, NetworkPacket.body("cancel" to id))

    fun reply(replyId: String, message: String): NetworkPacket =
        NetworkPacket(PacketType.NOTIFICATION_REPLY, NetworkPacket.body("requestReplyId" to replyId, "message" to message))
}
