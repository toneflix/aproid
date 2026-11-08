package com.toneflix.aproid.protocol

/** Shared clipboard text ("kdeconnect.clipboard" and "kdeconnect.clipboard.connect"). */
object Clipboard {
    fun packet(content: String): NetworkPacket =
        NetworkPacket(PacketType.CLIPBOARD, NetworkPacket.body("content" to content))

    /** Sent right after connecting, so the peer can tell whether it is newer than its own. */
    fun connectPacket(content: String, timestampMillis: Long): NetworkPacket =
        NetworkPacket(PacketType.CLIPBOARD_CONNECT, NetworkPacket.body("content" to content, "timestamp" to timestampMillis))

    /** The text in either clipboard packet, or null. */
    fun content(packet: NetworkPacket): String? {
        if (packet.type != PacketType.CLIPBOARD && packet.type != PacketType.CLIPBOARD_CONNECT) return null

        return packet.string("content")?.takeIf { it.isNotEmpty() }
    }
}
