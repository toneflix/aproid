package com.toneflix.flyylink.protocol

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.security.SecureRandom
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import kotlin.concurrent.thread
import kotlinx.serialization.json.JsonObject

/** Finds Google Cast TVs over mDNS. */
object CastFinder {
    /** Asks for [timeoutMs] and returns each TV once, sorted by name. Blocks, so call it off the main thread. */
    fun search(timeoutMs: Long = 3000): List<TvRenderer> {
        val found = LinkedHashMap<String, TvRenderer>()

        DatagramSocket().use { socket ->
            val group = InetAddress.getByName(Mdns.ADDRESS)
            val query = Mdns.query()
            val deadline = System.currentTimeMillis() + timeoutMs

            // Sent twice, since multicast over Wi-Fi drops packets.
            repeat(2) { runCatching { socket.send(DatagramPacket(query, query.size, group, Mdns.PORT)) } }

            val buffer = ByteArray(9000)
            while (true) {
                val left = deadline - System.currentTimeMillis()
                if (left <= 0) break

                socket.soTimeout = left.toInt()
                val packet = DatagramPacket(buffer, buffer.size)
                try {
                    socket.receive(packet)
                } catch (_: SocketTimeoutException) {
                    break
                }

                val records = Mdns.parse(packet.data.copyOf(packet.length))
                Mdns.castTvs(records, packet.address.hostAddress).forEach { found[it.id] = it }
            }
        }

        return found.values.sortedBy { it.name.lowercase() }
    }
}

/** A TLS connection to a Cast TV that answers its heartbeats and matches replies to requests. */
class CastChannel(endpoint: CastEndpoint) : Closeable {
    private val socket: SSLSocket
    private val input: DataInputStream
    private val output: DataOutputStream
    private val nextId = AtomicInteger(1)
    private val waiters = CopyOnWriteArrayList<Waiter>()
    private val pinger = Executors.newSingleThreadScheduledExecutor { Thread(it, "cast-ping").apply { isDaemon = true } }

    @Volatile
    var isOpen = true
        private set

    init {
        val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf(AcceptAnyCertificate), SecureRandom()) }

        socket = (context.socketFactory.createSocket() as SSLSocket).apply {
            connect(InetSocketAddress(endpoint.host, endpoint.port), 3000)
            startHandshake()
        }
        input = DataInputStream(BufferedInputStream(socket.inputStream))
        output = DataOutputStream(BufferedOutputStream(socket.outputStream))

        thread(isDaemon = true, name = "cast-reader") { readLoop() }
        pinger.scheduleAtFixedRate({ runCatching { send(GoogleCast.HEARTBEAT, GoogleCast.RECEIVER, GoogleCast.ping()) } }, 5, 5, TimeUnit.SECONDS)
    }

    fun newRequestId(): Int = nextId.getAndIncrement()

    @Synchronized
    fun send(namespace: String, destination: String, payload: JsonObject) {
        val bytes = CastMessage(GoogleCast.SENDER, destination, namespace, payload.toString()).encode()

        output.writeInt(bytes.size)
        output.write(bytes)
        output.flush()
    }

    /** Sends [payload] and waits for the first message that [match]es. */
    fun request(namespace: String, destination: String, payload: JsonObject, timeoutMs: Long = 5000, match: (JsonObject) -> Boolean): JsonObject {
        val waiter = Waiter(match)
        waiters += waiter

        try {
            send(namespace, destination, payload)

            return waiter.await(timeoutMs) ?: throw IOException("the TV didn't answer ${GoogleCast.type(payload)}")
        } finally {
            waiters -= waiter
        }
    }

    override fun close() {
        isOpen = false
        pinger.shutdownNow()
        runCatching { socket.close() }
        waiters.forEach { it.fail() }
    }

    private fun readLoop() {
        try {
            while (isOpen) {
                val length = input.readInt()
                if (length !in 0..(1 shl 20)) throw IOException("bad Cast frame")

                val bytes = ByteArray(length)
                input.readFully(bytes)

                val message = CastMessage.decode(bytes) ?: continue
                val json = GoogleCast.parse(message.payload) ?: continue
                val type = GoogleCast.type(json)

                when {
                    message.namespace == GoogleCast.HEARTBEAT && type == "PING" -> runCatching { send(GoogleCast.HEARTBEAT, message.source, GoogleCast.pong()) }
                    message.namespace == GoogleCast.CONNECTION && type == "CLOSE" -> break
                    else -> waiters.firstOrNull { !it.isDone && it.match(json) }?.complete(json)
                }
            }
        } catch (_: IOException) {
        } finally {
            close()
        }
    }

    private class Waiter(val match: (JsonObject) -> Boolean) {
        private val done = CountDownLatch(1)

        @Volatile
        private var result: JsonObject? = null

        val isDone: Boolean get() = done.count == 0L

        fun complete(json: JsonObject) {
            result = json
            done.countDown()
        }

        fun fail() = done.countDown()

        fun await(timeoutMs: Long): JsonObject? {
            done.await(timeoutMs, TimeUnit.MILLISECONDS)
            return result
        }
    }
}

/** Plays on a Cast TV through its Default Media Receiver. */
internal class CastControl(private val endpoint: CastEndpoint) : TvControl {
    private var channel: CastChannel? = null
    private var app: CastApp? = null
    private var mediaSessionId: Long? = null
    private var duration = 0L

    @Synchronized
    override fun play(url: String, title: String, mime: String, size: Long?) {
        channel?.close()

        val opened = CastChannel(endpoint)
        channel = opened
        opened.send(GoogleCast.CONNECTION, GoogleCast.RECEIVER, GoogleCast.connect())

        val id = opened.newRequestId()
        val reply = opened.request(GoogleCast.RECEIVER_NAMESPACE, GoogleCast.RECEIVER, GoogleCast.launch(id), timeoutMs = 15_000) {
            GoogleCast.mediaApp(it) != null || (GoogleCast.requestId(it) == id && GoogleCast.type(it) in GoogleCast.FAILURES)
        }
        val launched = GoogleCast.mediaApp(reply) ?: throw IOException("the TV couldn't open its media player")

        app = launched
        duration = 0
        opened.send(GoogleCast.CONNECTION, launched.transportId, GoogleCast.connect())

        mediaSessionId = GoogleCast.media(media(timeoutMs = 15_000) { GoogleCast.load(it, url, title, mime) })?.mediaSessionId
    }

    @Synchronized
    override fun resume() {
        media { GoogleCast.play(it, session()) }
    }

    @Synchronized
    override fun pause() {
        media { GoogleCast.pause(it, session()) }
    }

    @Synchronized
    override fun stop() {
        val opened = channel ?: return

        runCatching { media { GoogleCast.stop(it, session()) } }
        app?.let { running -> runCatching { receiver { GoogleCast.stopApp(it, running.sessionId) } } }
        opened.close()
        channel = null
        app = null
    }

    @Synchronized
    override fun seek(positionMs: Long) {
        media { GoogleCast.seek(it, session(), positionMs) }
    }

    @Synchronized
    override fun position(): CastPosition? = status()?.position?.let {
        if (it.duration > 0) duration = it.duration
        CastPosition(it.position, duration)
    }

    @Synchronized
    override fun state(): CastState? = if (channel?.isOpen != true) CastState.STOPPED else status()?.state

    @Synchronized
    override fun volume(): Int? = GoogleCast.volume(receiver { GoogleCast.receiverStatus(it) })

    @Synchronized
    override fun setVolume(volume: Int) {
        receiver { GoogleCast.setVolume(it, volume) }
    }

    private fun status(): CastMedia? {
        if (channel?.isOpen != true) return null

        return GoogleCast.media(media { GoogleCast.mediaStatus(it) })?.also { status -> status.mediaSessionId?.let { mediaSessionId = it } }
    }

    private fun session(): Long = mediaSessionId ?: throw IOException("nothing is playing on the TV")

    private fun media(timeoutMs: Long = 5000, build: (Int) -> JsonObject): JsonObject {
        val target = app ?: throw IOException("the TV's media player isn't open")

        return call(GoogleCast.MEDIA, target.transportId, timeoutMs, build)
    }

    private fun receiver(build: (Int) -> JsonObject): JsonObject = call(GoogleCast.RECEIVER_NAMESPACE, GoogleCast.RECEIVER, 5000, build)

    private fun call(namespace: String, destination: String, timeoutMs: Long, build: (Int) -> JsonObject): JsonObject {
        val opened = channel?.takeIf { it.isOpen } ?: throw IOException("not connected to the TV")
        val id = opened.newRequestId()
        val payload = build(id)

        val reply = opened.request(namespace, destination, payload, timeoutMs) { GoogleCast.requestId(it) == id }
        if (GoogleCast.type(reply) in GoogleCast.FAILURES) throw IOException("the TV refused ${GoogleCast.type(payload)}")

        return reply
    }
}
