package com.toneflix.flyylink.protocol

/** One media player on the phone, as "kdeconnect.mpris" describes it. Times are in milliseconds. */
data class MediaPlayer(
    val name: String,
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val isPlaying: Boolean = false,
    val position: Long = 0,
    val length: Long = 0,
    val volume: Int? = null,
    val canPlay: Boolean = true,
    val canPause: Boolean = true,
    val canGoNext: Boolean = false,
    val canGoPrevious: Boolean = false,
    val canSeek: Boolean = false,
    val albumArtUrl: String? = null,
) {
    fun toPacket(): NetworkPacket = NetworkPacket(
        PacketType.MPRIS,
        NetworkPacket.body(
            "player" to name,
            "title" to title,
            "artist" to artist,
            "album" to album,
            "isPlaying" to isPlaying,
            "pos" to position,
            "length" to length,
            "volume" to volume,
            "canPlay" to canPlay,
            "canPause" to canPause,
            "canGoNext" to canGoNext,
            "canGoPrevious" to canGoPrevious,
            "canSeek" to canSeek,
            "albumArtUrl" to albumArtUrl,
        ),
    )

    companion object {
        /** Null unless the packet describes a player. */
        fun fromPacket(packet: NetworkPacket): MediaPlayer? {
            if (packet.type != PacketType.MPRIS || packet.bool("transferringAlbumArt") == true) return null

            val name = packet.string("player") ?: return null

            return MediaPlayer(
                name = name,
                title = packet.string("title") ?: "",
                artist = packet.string("artist") ?: "",
                album = packet.string("album") ?: "",
                isPlaying = packet.bool("isPlaying") ?: false,
                position = packet.long("pos") ?: 0,
                length = packet.long("length") ?: 0,
                volume = packet.int("volume"),
                canPlay = packet.bool("canPlay") ?: true,
                canPause = packet.bool("canPause") ?: true,
                canGoNext = packet.bool("canGoNext") ?: false,
                canGoPrevious = packet.bool("canGoPrevious") ?: false,
                canSeek = packet.bool("canSeek") ?: false,
                albumArtUrl = packet.string("albumArtUrl")?.takeIf { it.isNotEmpty() },
            )
        }
    }
}

enum class MediaAction(val wire: String) {
    PLAY_PAUSE("PlayPause"),
    PLAY("Play"),
    PAUSE("Pause"),
    NEXT("Next"),
    PREVIOUS("Previous"),
    STOP("Stop");

    companion object {
        fun fromWire(wire: String?): MediaAction? = entries.firstOrNull { it.wire == wire }
    }
}

/** What the Mac asks of the phone's players ("kdeconnect.mpris.request"). */
data class MediaRequest(
    val player: String? = null,
    val wantsPlayerList: Boolean = false,
    val wantsNowPlaying: Boolean = false,
    val action: MediaAction? = null,
    val seekTo: Long? = null,
    val volume: Int? = null,
    val albumArtUrl: String? = null,
) {
    fun toPacket(): NetworkPacket = NetworkPacket(
        PacketType.MPRIS_REQUEST,
        NetworkPacket.body(
            "player" to player,
            "requestPlayerList" to wantsPlayerList.takeIf { it },
            "requestNowPlaying" to wantsNowPlaying.takeIf { it },
            "requestVolume" to wantsNowPlaying.takeIf { it },
            "action" to action?.wire,
            "SetPosition" to seekTo,
            "setVolume" to volume,
            "albumArtUrl" to albumArtUrl,
        ),
    )

    companion object {
        fun playerList() = MediaRequest(wantsPlayerList = true)

        fun nowPlaying(player: String) = MediaRequest(player, wantsNowPlaying = true)

        fun action(player: String, action: MediaAction) = MediaRequest(player, action = action)

        fun seek(player: String, position: Long) = MediaRequest(player, seekTo = position)

        fun volume(player: String, volume: Int) = MediaRequest(player, volume = volume.coerceIn(0, 100))

        fun albumArt(player: String, url: String) = MediaRequest(player, albumArtUrl = url)

        fun fromPacket(packet: NetworkPacket): MediaRequest? {
            if (packet.type != PacketType.MPRIS_REQUEST) return null

            return MediaRequest(
                player = packet.string("player"),
                wantsPlayerList = packet.bool("requestPlayerList") ?: false,
                wantsNowPlaying = packet.bool("requestNowPlaying") ?: false,
                action = MediaAction.fromWire(packet.string("action")),
                seekTo = packet.long("SetPosition"),
                volume = packet.int("setVolume"),
                albumArtUrl = packet.string("albumArtUrl"),
            )
        }
    }
}

/** The other "kdeconnect.mpris" packets: the list of players, and album art sent as a payload. */
object Media {
    fun playerListPacket(names: List<String>): NetworkPacket = NetworkPacket(
        PacketType.MPRIS,
        NetworkPacket.body("playerList" to names, "supportAlbumArtPayload" to true),
    )

    /** The player names, or null if the packet has no list. */
    fun playerList(packet: NetworkPacket): List<String>? {
        if (packet.type != PacketType.MPRIS || !packet.body.containsKey("playerList")) return null

        return packet.stringList("playerList")
    }

    /** Announces album art for [url]. Send it with [Device.sendWithPayload]. */
    fun albumArtPacket(player: String, url: String): NetworkPacket = NetworkPacket(
        PacketType.MPRIS,
        NetworkPacket.body("player" to player, "albumArtUrl" to url, "transferringAlbumArt" to true),
    )

    /** The art's url when the packet carries album art. */
    fun albumArtUrl(packet: NetworkPacket): String? {
        if (packet.type != PacketType.MPRIS || packet.bool("transferringAlbumArt") != true) return null

        return packet.string("albumArtUrl")
    }
}
