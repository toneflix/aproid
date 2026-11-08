package com.toneflix.aproid.protocol

/** What a "kdeconnect.share.request" carries: a file, a link or some text. */
sealed interface Share {
    data class File(val name: String, val size: Long) : Share {
        /** The name without any folders, so a peer can't write outside the download folder. */
        val safeName: String
            get() = name.substringAfterLast('/').substringAfterLast('\\').trimStart('.').ifBlank { "file" }
    }

    data class Link(val url: String) : Share

    data class Text(val text: String) : Share

    companion object {
        /** The packet announcing a file. Send it with [Device.sendWithPayload], which adds the payload. */
        fun file(name: String, size: Long, lastModifiedMillis: Long? = null): NetworkPacket = NetworkPacket(
            PacketType.SHARE_REQUEST,
            NetworkPacket.body(
                "filename" to name,
                "lastModified" to lastModifiedMillis,
                "numberOfFiles" to 1,
                "totalPayloadSize" to size,
            ),
        )

        fun link(url: String): NetworkPacket = NetworkPacket(PacketType.SHARE_REQUEST, NetworkPacket.body("url" to url))

        fun text(text: String): NetworkPacket = NetworkPacket(PacketType.SHARE_REQUEST, NetworkPacket.body("text" to text))

        fun fromPacket(packet: NetworkPacket): Share? {
            if (packet.type != PacketType.SHARE_REQUEST) return null

            packet.string("filename")?.let { name ->
                val size = packet.payloadSize ?: return null
                return File(name, size)
            }
            packet.string("url")?.let { return Link(it) }
            packet.string("text")?.let { return Text(it) }

            return null
        }
    }
}
