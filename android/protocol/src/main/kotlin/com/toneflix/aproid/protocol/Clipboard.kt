package com.toneflix.aproid.protocol

/** A copied picture or file. [safeName] has no folders, so it can't be saved outside the target folder. */
data class ClipboardFile(val name: String, val mimeType: String) {
    val safeName: String get() = Share.File(name, 0).safeName
}

/** Shared clipboard text ("kdeconnect.clipboard" and "kdeconnect.clipboard.connect"), and copied files ("aproid.clipboard.file"). */
object Clipboard {
    /** Bigger copies are left alone, so copying a film in Finder doesn't start a long transfer. */
    const val FILE_LIMIT = 50L * 1024 * 1024

    /** Announces a copied file. Send it with [Device.sendWithPayload]. */
    fun filePacket(name: String, mimeType: String): NetworkPacket =
        NetworkPacket(PacketType.CLIPBOARD_FILE, NetworkPacket.body("name" to name, "mimeType" to mimeType))

    fun file(packet: NetworkPacket): ClipboardFile? {
        if (packet.type != PacketType.CLIPBOARD_FILE || packet.payloadSize == null) return null

        val name = packet.string("name") ?: return null
        return ClipboardFile(name, packet.string("mimeType") ?: "application/octet-stream")
    }

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
