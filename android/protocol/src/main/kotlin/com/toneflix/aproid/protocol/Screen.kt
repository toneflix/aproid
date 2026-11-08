package com.toneflix.aproid.protocol

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * Mirroring the phone's screen on the Mac. The Mac asks with [start]; the phone answers with an
 * "aproid.screen" packet whose payload is a live H.264 stream of [ScreenFrame]s, sent until either side stops.
 */
object Screen {
    /** The payload size of a live stream: read until the sender closes it. */
    const val STREAM = -1L

    const val MAX_SIZE = 1600
    const val BITRATE = 8_000_000

    enum class Action(val wire: String) {
        START("start"),
        STOP("stop"),
    }

    data class Request(val action: Action, val maxSize: Int = MAX_SIZE, val bitrate: Int = BITRATE)

    /** What the phone is sending. Sizes are in pixels; [running] is false once mirroring stops. */
    data class Info(val width: Int, val height: Int, val running: Boolean)

    fun start(maxSize: Int = MAX_SIZE, bitrate: Int = BITRATE): NetworkPacket = NetworkPacket(
        PacketType.SCREEN_REQUEST,
        NetworkPacket.body("action" to Action.START.wire, "maxSize" to maxSize, "bitrate" to bitrate),
    )

    fun stop(): NetworkPacket = NetworkPacket(PacketType.SCREEN_REQUEST, NetworkPacket.body("action" to Action.STOP.wire))

    fun request(packet: NetworkPacket): Request? {
        if (packet.type != PacketType.SCREEN_REQUEST) return null

        val action = Action.entries.firstOrNull { it.wire == packet.string("action") } ?: return null
        return Request(
            action,
            (packet.int("maxSize") ?: MAX_SIZE).coerceIn(320, 4096),
            (packet.int("bitrate") ?: BITRATE).coerceIn(500_000, 50_000_000),
        )
    }

    /** Announces a stream; send it with [STREAM] as the payload size. */
    fun started(width: Int, height: Int): NetworkPacket = NetworkPacket(
        PacketType.SCREEN,
        NetworkPacket.body("width" to width, "height" to height, "codec" to "h264", "running" to true),
    )

    fun stopped(): NetworkPacket = NetworkPacket(PacketType.SCREEN, NetworkPacket.body("running" to false))

    fun info(packet: NetworkPacket): Info? {
        if (packet.type != PacketType.SCREEN) return null

        return Info(packet.int("width") ?: 0, packet.int("height") ?: 0, packet.bool("running") ?: false)
    }
}

/**
 * One encoded piece of the screen stream. On the wire each is a 13 byte header (size, then the
 * presentation time in microseconds, then [flags]) followed by the H.264 data in Annex B form.
 */
class ScreenFrame(val data: ByteArray, val timeUs: Long, val flags: Int) {
    /** The SPS and PPS the decoder needs before any picture. */
    val isConfig: Boolean get() = flags and CONFIG != 0
    val isKey: Boolean get() = flags and KEY != 0

    fun header(): ByteArray = ByteBuffer.allocate(HEADER).putInt(data.size).putLong(timeUs).put(flags.toByte()).array()

    override fun equals(other: Any?) =
        other is ScreenFrame && other.timeUs == timeUs && other.flags == flags && other.data.contentEquals(data)

    override fun hashCode() = data.contentHashCode() * 31 + timeUs.hashCode() * 7 + flags

    companion object {
        const val HEADER = 13
        const val CONFIG = 1
        const val KEY = 2

        /** Larger than any real frame; anything bigger means the stream is corrupt. */
        const val MAX_SIZE = 16 * 1024 * 1024
    }

    /** Collects stream bytes, however they are split, back into whole frames. */
    class Reader {
        private val pending = ByteArrayOutputStream()

        fun feed(bytes: ByteArray, offset: Int = 0, length: Int = bytes.size): List<ScreenFrame> {
            pending.write(bytes, offset, length)

            val buffer = ByteBuffer.wrap(pending.toByteArray())
            val frames = mutableListOf<ScreenFrame>()

            while (buffer.remaining() >= HEADER) {
                buffer.mark()
                val size = buffer.int
                if (size < 0 || size > MAX_SIZE) throw ProtocolException("screen frame of $size bytes")

                val time = buffer.long
                val flags = buffer.get().toInt() and 0xFF
                if (buffer.remaining() < size) {
                    buffer.reset()
                    break
                }

                frames += ScreenFrame(ByteArray(size).also { buffer.get(it) }, time, flags)
            }

            pending.reset()
            pending.write(buffer.array(), buffer.position(), buffer.remaining())

            return frames
        }
    }
}

/** A touch, key or typed text from the Mac. Positions are fractions of the screen, 0 to 1 from the top left. */
sealed class ScreenInput {
    data class Tap(val x: Double, val y: Double) : ScreenInput()

    data class LongPress(val x: Double, val y: Double) : ScreenInput()

    data class Swipe(val x: Double, val y: Double, val toX: Double, val toY: Double, val durationMs: Long) : ScreenInput()

    data class Text(val text: String) : ScreenInput()

    data class Key(val key: String) : ScreenInput()

    fun toPacket(): NetworkPacket = NetworkPacket(
        PacketType.SCREEN_INPUT,
        when (this) {
            is Tap -> NetworkPacket.body("action" to "tap", "x" to x, "y" to y)
            is LongPress -> NetworkPacket.body("action" to "longPress", "x" to x, "y" to y)
            is Swipe -> NetworkPacket.body("action" to "swipe", "x" to x, "y" to y, "toX" to toX, "toY" to toY, "duration" to durationMs)
            is Text -> NetworkPacket.body("action" to "text", "text" to text)
            is Key -> NetworkPacket.body("action" to "key", "key" to key)
        },
    )

    companion object {
        const val BACK = "back"
        const val HOME = "home"
        const val RECENTS = "recents"
        const val NOTIFICATIONS = "notifications"
        const val ENTER = "enter"
        const val DELETE = "delete"

        val keys = setOf(BACK, HOME, RECENTS, NOTIFICATIONS, ENTER, DELETE)

        fun fromPacket(packet: NetworkPacket): ScreenInput? {
            if (packet.type != PacketType.SCREEN_INPUT) return null

            fun fraction(key: String) = packet.double(key)?.takeIf { it in 0.0..1.0 }

            return when (packet.string("action")) {
                "tap" -> Tap(fraction("x") ?: return null, fraction("y") ?: return null)
                "longPress" -> LongPress(fraction("x") ?: return null, fraction("y") ?: return null)
                "swipe" -> Swipe(
                    fraction("x") ?: return null,
                    fraction("y") ?: return null,
                    fraction("toX") ?: return null,
                    fraction("toY") ?: return null,
                    (packet.long("duration") ?: 200).coerceIn(10, 5000),
                )
                "text" -> packet.string("text")?.takeIf { it.isNotEmpty() }?.let(::Text)
                "key" -> packet.string("key")?.takeIf { it in keys }?.let(::Key)
                else -> null
            }
        }
    }
}
