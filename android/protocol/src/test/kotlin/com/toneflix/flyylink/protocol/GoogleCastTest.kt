package com.toneflix.flyylink.protocol

import java.io.DataInputStream
import java.io.DataOutputStream
import java.security.KeyStore
import java.util.Collections
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import kotlin.concurrent.thread
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GoogleCastTest {
    private val pingHex =
        "0800120873656e6465722d301a0a72656365697665722d30222775726e3a782d636173743a636f6d2e676f6f676c652e636173742e74702e6865617274626561742800320f7b2274797065223a2250494e47227d"

    // One answer from a Cast TV: a PTR to its instance, then TXT, SRV and A records, with compressed names.
    private val answerHex =
        "0000840000000001000000030b5f676f6f676c6563617374045f746370056c6f63616c00000c000100000078001e1b416e64726f69642d54562d31613262336334643565366637613862c00cc02e0010800100001194003e1369643d316132623363346435653666376138620f6d643d4869536d617274545620413411666e3d4c6976696e6720526f6f6d2054560763613d32303533c02e00218001000000780016000000001f49083161326233633464056c6f63616c00c0a800018001000000780004c0a8011e"

    @Test fun encodesCastMessages() {
        val message = CastMessage(GoogleCast.SENDER, GoogleCast.RECEIVER, GoogleCast.HEARTBEAT, """{"type":"PING"}""")

        assertEquals(pingHex, message.encode().hex())
        assertEquals(message, CastMessage.decode(pingHex.unhex()))
    }

    @Test fun ignoresBrokenCastMessages() {
        assertNull(CastMessage.decode(pingHex.unhex().copyOf(20)))
        assertNull(CastMessage.decode(byteArrayOf(0x08, 0x00)))
    }

    @Test fun mdnsQueryAsksForCastTvs() {
        assertEquals("0000000000010000000000000b5f676f6f676c6563617374045f746370056c6f63616c00000c8001", Mdns.query().hex())
    }

    @Test fun readsCastTvsFromMdnsAnswers() {
        val tvs = Mdns.castTvs(Mdns.parse(answerHex.unhex()), sender = "192.168.1.99")

        assertEquals(listOf(TvRenderer("cast:1a2b3c4d5e6f7a8b", "Living Room TV", cast = CastEndpoint("192.168.1.30", 8009))), tvs)
        assertEquals("192.168.1.30", tvs.single().host)
    }

    @Test fun ignoresMdnsQuestions() {
        assertTrue(Mdns.parse(Mdns.query()).isEmpty())
        assertTrue(Mdns.parse(byteArrayOf(1, 2, 3)).isEmpty())
    }

    @Test fun loadsMediaOnTheDefaultReceiver() {
        val load = GoogleCast.load(7, "http://192.168.1.5:4000/t/song.mp3", "Song", "audio/mpeg")
        val media = load["media"]!!.jsonObject

        assertEquals("LOAD", GoogleCast.type(load))
        assertEquals(7, GoogleCast.requestId(load))
        assertTrue(load["autoplay"]!!.jsonPrimitive.boolean)
        assertEquals("http://192.168.1.5:4000/t/song.mp3", media["contentId"]!!.jsonPrimitive.content)
        assertEquals("audio/mpeg", media["contentType"]!!.jsonPrimitive.content)
        assertEquals(3, media["metadata"]!!.jsonObject["metadataType"]!!.jsonPrimitive.int)
        assertEquals("Song", media["metadata"]!!.jsonObject["title"]!!.jsonPrimitive.content)
        assertEquals("CC1AD845", GoogleCast.launch(1)["appId"]!!.jsonPrimitive.content)
        assertEquals(12.5, GoogleCast.seek(2, 3, 12_500)["currentTime"]!!.jsonPrimitive.double, 0.0)
    }

    @Test fun readsMediaStatus() {
        val status = GoogleCast.parse(
            """{"type":"MEDIA_STATUS","requestId":4,"status":[{"mediaSessionId":3,"playerState":"PAUSED","currentTime":12.5,"media":{"duration":60}}]}""",
        )!!

        assertEquals(CastMedia(3, CastState.PAUSED, CastPosition(12_500, 60_000)), GoogleCast.media(status))
        assertEquals(CastMedia(null, CastState.STOPPED, null), GoogleCast.media(GoogleCast.parse("""{"type":"MEDIA_STATUS","status":[]}""")!!))
        assertEquals(CastState.LOADING, GoogleCast.state("BUFFERING"))
        assertNull(GoogleCast.media(GoogleCast.parse("""{"type":"RECEIVER_STATUS"}""")!!))
    }

    @Test fun readsTheRunningMediaReceiver() {
        val status = GoogleCast.parse(
            """{"type":"RECEIVER_STATUS","requestId":1,"status":{"volume":{"level":0.35},"applications":[""" +
                """{"appId":"E8C28D3C","sessionId":"other","transportId":"other-1"},""" +
                """{"appId":"CC1AD845","sessionId":"abc","transportId":"web-5"}]}}""",
        )!!

        assertEquals(CastApp("abc", "web-5"), GoogleCast.mediaApp(status))
        assertEquals(35, GoogleCast.volume(status))
        assertNull(GoogleCast.mediaApp(GoogleCast.parse("""{"type":"RECEIVER_STATUS","status":{"applications":[]}}""")!!))
    }

    @Test fun prefersCastWhenATvAnswersBothWays() {
        val castTv = TvRenderer("cast:1", "Living Room TV", cast = CastEndpoint("192.168.1.30"))
        val sameTv = TvRenderer("uuid:a", "Hisense DMR", "http://192.168.1.30:9197/av")
        val other = TvRenderer("uuid:b", "bedroom", "http://192.168.1.31/av")

        assertEquals(listOf(other, castTv), TvFinder.merge(listOf(sameTv, other), listOf(castTv)))
    }

    @Test fun playsAndControlsOnACastTv() {
        val tv = FakeCastTv()

        try {
            val player = TvPlayer(TvRenderer("cast:1", "TV", cast = CastEndpoint("127.0.0.1", tv.port)))

            player.play("http://127.0.0.1/t/clip.mp4", "Clip", "video/mp4")
            player.pause()
            player.seek(30_000)

            assertEquals(CastState.PAUSED, player.state())
            assertEquals(CastPosition(30_000, 120_000), player.position())

            player.stop()

            assertEquals(listOf("CONNECT", "LAUNCH", "CONNECT", "LOAD", "PAUSE", "SEEK", "GET_STATUS", "GET_STATUS", "STOP", "STOP"), tv.received)
            assertEquals(CastState.STOPPED, player.state())
        } finally {
            tv.close()
        }
    }

    /** Answers like a Cast TV's Default Media Receiver. */
    private class FakeCastTv {
        val received: MutableList<String> = Collections.synchronizedList(mutableListOf())
        private val server: SSLServerSocket
        private var state = "PLAYING"
        private var time = 0.0

        val port: Int get() = server.localPort

        init {
            val certificate = DeviceCertificate.generate("cast-tv")
            val keys = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
                load(null, null)
                setKeyEntry("tv", certificate.privateKey, CharArray(0), arrayOf(certificate.certificate))
            }
            val factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(keys, CharArray(0)) }
            val context = SSLContext.getInstance("TLS").apply { init(factory.keyManagers, null, null) }

            server = context.serverSocketFactory.createServerSocket(0) as SSLServerSocket
            thread(isDaemon = true) { runCatching { server.accept().use(::serve) } }
        }

        fun close() = runCatching { server.close() }

        private fun serve(socket: java.net.Socket) {
            val input = DataInputStream(socket.getInputStream())
            val output = DataOutputStream(socket.getOutputStream())

            fun reply(to: CastMessage, payload: String) {
                val bytes = CastMessage(to.destination, to.source, to.namespace, payload).encode()
                output.writeInt(bytes.size)
                output.write(bytes)
                output.flush()
            }

            while (true) {
                val bytes = ByteArray(input.readInt()).also(input::readFully)
                val message = CastMessage.decode(bytes)!!
                val json: JsonObject = GoogleCast.parse(message.payload)!!
                val type = GoogleCast.type(json)!!
                val id = GoogleCast.requestId(json)
                if (type == "PING") continue

                received += type
                when (type) {
                    "LAUNCH" -> reply(message, """{"type":"RECEIVER_STATUS","requestId":$id,"status":{"applications":[{"appId":"CC1AD845","sessionId":"s1","transportId":"web-1"}]}}""")
                    "PAUSE" -> state = "PAUSED"
                    "SEEK" -> time = json["currentTime"]!!.jsonPrimitive.double
                    "STOP" -> state = "IDLE"
                }

                if (message.namespace == GoogleCast.MEDIA) {
                    reply(message, """{"type":"MEDIA_STATUS","requestId":$id,"status":[{"mediaSessionId":9,"playerState":"$state","currentTime":$time,"media":{"duration":120}}]}""")
                } else if (type == "STOP") {
                    reply(message, """{"type":"RECEIVER_STATUS","requestId":$id,"status":{"applications":[]}}""")
                }
            }
        }
    }

    private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }

    private fun String.unhex(): ByteArray = chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
