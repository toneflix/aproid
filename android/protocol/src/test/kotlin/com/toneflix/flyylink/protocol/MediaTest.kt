package com.toneflix.flyylink.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MediaTest {
    private val player = MediaPlayer(
        name = "Spotify",
        title = "Midnight City",
        artist = "M83",
        album = "Hurry Up, We're Dreaming",
        isPlaying = true,
        position = 61_000,
        length = 243_000,
        volume = 70,
        canGoNext = true,
        canGoPrevious = true,
        canSeek = true,
        albumArtUrl = "flyylink://art/1f2e",
    )

    private fun wire(packet: NetworkPacket) = NetworkPacket.parse(packet.serialize())

    @Test fun playerRoundTrips() {
        assertEquals(player, MediaPlayer.fromPacket(wire(player.toPacket())))
    }

    @Test fun requestsRoundTrip() {
        val requests = listOf(
            MediaRequest.playerList(),
            MediaRequest.nowPlaying("Spotify"),
            MediaRequest.action("Spotify", MediaAction.NEXT),
            MediaRequest.seek("Spotify", 90_000),
            MediaRequest.volume("Spotify", 140),
            MediaRequest.albumArt("Spotify", "flyylink://art/1f2e"),
        )

        requests.forEach { assertEquals(it, MediaRequest.fromPacket(wire(it.toPacket()))) }
        assertEquals(100, MediaRequest.volume("Spotify", 140).volume)
    }

    @Test fun readsKdeConnectRequest() {
        val packet = NetworkPacket.parse("""{"id":1,"type":"kdeconnect.mpris.request","body":{"player":"VLC","action":"PlayPause"}}""")

        val request = MediaRequest.fromPacket(packet)

        assertEquals("VLC", request?.player)
        assertEquals(MediaAction.PLAY_PAUSE, request?.action)
    }

    @Test fun playerListAndAlbumArtAreNotPlayers() {
        val list = wire(Media.playerListPacket(listOf("Spotify", "YouTube Music")))
        val art = wire(Media.albumArtPacket("Spotify", "flyylink://art/1f2e"))

        assertEquals(listOf("Spotify", "YouTube Music"), Media.playerList(list))
        assertNull(MediaPlayer.fromPacket(list))
        assertNull(MediaPlayer.fromPacket(art))
        assertNull(Media.playerList(player.toPacket()))
        assertEquals("flyylink://art/1f2e", Media.albumArtUrl(art))
    }
}
