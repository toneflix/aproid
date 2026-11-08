package com.toneflix.aproid.protocol

/** What a "kdeconnect.share.request" carries: a file, a link or some text. */
sealed interface Share {
    /**
     * [transferId] lets an interrupted file be resumed; [offset] is where this payload starts in the file,
     * so [size] is only what is left. Both are our own fields, which KDE Connect ignores.
     */
    data class File(val name: String, val size: Long, val transferId: String? = null, val offset: Long = 0) : Share {
        /** The name without any folders, so a peer can't write outside the download folder. */
        val safeName: String
            get() = name.substringAfterLast('/').substringAfterLast('\\').trimStart('.').ifBlank { "file" }
    }

    data class Link(val url: String) : Share

    data class Text(val text: String) : Share

    companion object {
        /** The packet announcing a file. Send it with [Device.sendWithPayload], which adds the payload. */
        fun file(
            name: String,
            size: Long,
            lastModifiedMillis: Long? = null,
            transferId: String? = null,
            offset: Long = 0,
        ): NetworkPacket = NetworkPacket(
            PacketType.SHARE_REQUEST,
            NetworkPacket.body(
                "filename" to name,
                "lastModified" to lastModifiedMillis,
                "numberOfFiles" to 1,
                "totalPayloadSize" to size,
                "aproid.transferId" to transferId,
                "aproid.offset" to offset.takeIf { it > 0 },
            ),
        )

        /** Asks the sender for the rest of [transferId], from byte [offset]. */
        fun resume(transferId: String, offset: Long): NetworkPacket =
            NetworkPacket(PacketType.SHARE_RESUME, NetworkPacket.body("transferId" to transferId, "offset" to offset))

        /** The transfer and offset a resume packet asks for. */
        fun resumeRequest(packet: NetworkPacket): Pair<String, Long>? {
            if (packet.type != PacketType.SHARE_RESUME) return null

            val id = packet.string("transferId") ?: return null
            val offset = packet.long("offset")?.takeIf { it >= 0 } ?: return null
            return id to offset
        }

        fun link(url: String): NetworkPacket = NetworkPacket(PacketType.SHARE_REQUEST, NetworkPacket.body("url" to url))

        fun text(text: String): NetworkPacket = NetworkPacket(PacketType.SHARE_REQUEST, NetworkPacket.body("text" to text))

        fun fromPacket(packet: NetworkPacket): Share? {
            if (packet.type != PacketType.SHARE_REQUEST) return null

            packet.string("filename")?.let { name ->
                val size = packet.payloadSize ?: return null
                val offset = packet.long("aproid.offset")?.coerceAtLeast(0) ?: 0
                return File(name, size, packet.string("aproid.transferId"), offset)
            }
            packet.string("url")?.let { return Link(it) }
            packet.string("text")?.let { return Text(it) }

            return null
        }
    }
}
