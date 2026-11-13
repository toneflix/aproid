package com.toneflix.flyylink.protocol

/**
 * A press on the remote a phone shows for a TV ("flyylink.remote"): a [Key], or [Text] typed into the TV's
 * focused field. Mirrors TvRemote.swift and TvRemote.cs.
 */
sealed class TvRemote {
    data class Key(val key: String) : TvRemote()

    data class Text(val text: String) : TvRemote()

    fun toPacket(): NetworkPacket = NetworkPacket(
        PacketType.REMOTE,
        when (this) {
            is Key -> NetworkPacket.body("action" to "key", "key" to key)
            is Text -> NetworkPacket.body("action" to "text", "text" to text)
        },
    )

    companion object {
        const val UP = "up"
        const val DOWN = "down"
        const val LEFT = "left"
        const val RIGHT = "right"
        const val SELECT = "select"
        const val BACK = "back"
        const val HOME = "home"
        const val MENU = "menu"
        const val PLAY_PAUSE = "playPause"
        const val NEXT = "next"
        const val PREVIOUS = "previous"
        const val VOLUME_UP = "volumeUp"
        const val VOLUME_DOWN = "volumeDown"
        const val MUTE = "mute"
        const val DELETE = "delete"
        const val ENTER = "enter"

        val keys = setOf(UP, DOWN, LEFT, RIGHT, SELECT, BACK, HOME, MENU, PLAY_PAUSE, NEXT, PREVIOUS, VOLUME_UP, VOLUME_DOWN, MUTE, DELETE, ENTER)

        /** Longer text than this in one packet is treated as nonsense. */
        const val MAX_TEXT = 1000

        fun fromPacket(packet: NetworkPacket): TvRemote? {
            if (packet.type != PacketType.REMOTE) return null

            return when (packet.string("action")) {
                "key" -> packet.string("key")?.takeIf { it in keys }?.let(::Key)
                "text" -> packet.string("text")?.takeIf { it.isNotEmpty() && it.length <= MAX_TEXT }?.let(::Text)
                else -> null
            }
        }
    }
}
