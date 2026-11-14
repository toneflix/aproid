package com.toneflix.flyylink.protocol

import java.io.ByteArrayOutputStream
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/** Where a Google Cast TV listens. */
data class CastEndpoint(val host: String, val port: Int = GoogleCast.PORT)

/** Google Cast: the messages that tell a Cast TV's built-in media player what to play. */
object GoogleCast {
    const val PORT = 8009
    const val SERVICE = "_googlecast._tcp.local"

    /** Google's Default Media Receiver, the player every Cast TV has. */
    const val MEDIA_RECEIVER = "CC1AD845"

    const val SENDER = "sender-0"
    const val RECEIVER = "receiver-0"

    const val CONNECTION = "urn:x-cast:com.google.cast.tp.connection"
    const val HEARTBEAT = "urn:x-cast:com.google.cast.tp.heartbeat"
    const val RECEIVER_NAMESPACE = "urn:x-cast:com.google.cast.receiver"
    const val MEDIA = "urn:x-cast:com.google.cast.media"

    /** Replies that mean a request failed. */
    val FAILURES = setOf("LAUNCH_ERROR", "LOAD_FAILED", "LOAD_CANCELLED", "INVALID_REQUEST", "INVALID_PLAYER_STATE")

    fun connect(): JsonObject = message("CONNECT")

    fun ping(): JsonObject = message("PING")

    fun pong(): JsonObject = message("PONG")

    fun launch(requestId: Int): JsonObject = buildJsonObject {
        put("type", "LAUNCH")
        put("requestId", requestId)
        put("appId", MEDIA_RECEIVER)
    }

    fun receiverStatus(requestId: Int): JsonObject = request("GET_STATUS", requestId)

    fun stopApp(requestId: Int, sessionId: String): JsonObject = buildJsonObject {
        put("type", "STOP")
        put("requestId", requestId)
        put("sessionId", sessionId)
    }

    fun setVolume(requestId: Int, volume: Int): JsonObject = buildJsonObject {
        put("type", "SET_VOLUME")
        put("requestId", requestId)
        putJsonObject("volume") { put("level", volume.coerceIn(0, 100) / 100.0) }
    }

    fun load(requestId: Int, url: String, title: String, mime: String): JsonObject = buildJsonObject {
        put("type", "LOAD")
        put("requestId", requestId)
        put("autoplay", true)
        putJsonObject("media") {
            put("contentId", url)
            put("contentType", mime)
            put("streamType", "BUFFERED")
            putJsonObject("metadata") {
                put("metadataType", metadataType(mime))
                put("title", title)
            }
        }
    }

    fun mediaStatus(requestId: Int, mediaSessionId: Long? = null): JsonObject = mediaCall("GET_STATUS", requestId, mediaSessionId)

    fun play(requestId: Int, mediaSessionId: Long): JsonObject = mediaCall("PLAY", requestId, mediaSessionId)

    fun pause(requestId: Int, mediaSessionId: Long): JsonObject = mediaCall("PAUSE", requestId, mediaSessionId)

    fun stop(requestId: Int, mediaSessionId: Long): JsonObject = mediaCall("STOP", requestId, mediaSessionId)

    fun seek(requestId: Int, mediaSessionId: Long, positionMs: Long): JsonObject = buildJsonObject {
        put("type", "SEEK")
        put("requestId", requestId)
        put("mediaSessionId", mediaSessionId)
        put("currentTime", positionMs.coerceAtLeast(0) / 1000.0)
    }

    /** The JSON of a message, or null when it isn't a JSON object. */
    fun parse(payload: String): JsonObject? = runCatching { Json.parseToJsonElement(payload).jsonObject }.getOrNull()

    fun type(message: JsonObject): String? = message["type"]?.jsonPrimitive?.contentOrNullSafe()

    fun requestId(message: JsonObject): Int? = message["requestId"]?.jsonPrimitive?.longOrNull?.toInt()

    /** The running Default Media Receiver in a RECEIVER_STATUS, or null while it isn't running. */
    fun mediaApp(message: JsonObject): CastApp? {
        if (type(message) != "RECEIVER_STATUS") return null

        val apps = runCatching { message["status"]!!.jsonObject["applications"]!!.jsonArray }.getOrNull() ?: return null

        return apps.map { it.jsonObject }
            .firstOrNull { it["appId"]?.jsonPrimitive?.contentOrNullSafe() == MEDIA_RECEIVER }
            ?.let { app ->
                val session = app["sessionId"]?.jsonPrimitive?.contentOrNullSafe() ?: return null
                val transport = app["transportId"]?.jsonPrimitive?.contentOrNullSafe() ?: return null
                CastApp(session, transport)
            }
    }

    /** The TV's volume from 0 to 100 in a RECEIVER_STATUS. */
    fun volume(message: JsonObject): Int? {
        if (type(message) != "RECEIVER_STATUS") return null

        val level = runCatching { message["status"]!!.jsonObject["volume"]!!.jsonObject["level"]!!.jsonPrimitive.doubleOrNull }.getOrNull() ?: return null

        return Math.round(level * 100).toInt()
    }

    /** What the player is doing in a MEDIA_STATUS. Null unless [message] is one. */
    fun media(message: JsonObject): CastMedia? {
        if (type(message) != "MEDIA_STATUS") return null

        val status = runCatching { message["status"]!!.jsonArray.firstOrNull()?.jsonObject }.getOrNull() ?: return CastMedia(null, CastState.STOPPED, null)
        val seconds = { value: JsonPrimitive? -> value?.doubleOrNull?.let { (it * 1000).toLong() } }

        val position = seconds(status["currentTime"]?.jsonPrimitive)
        val duration = runCatching { seconds(status["media"]?.jsonObject?.get("duration")?.jsonPrimitive) }.getOrNull()

        return CastMedia(
            mediaSessionId = status["mediaSessionId"]?.jsonPrimitive?.longOrNull,
            state = state(status["playerState"]?.jsonPrimitive?.contentOrNullSafe()),
            position = position?.let { CastPosition(it, duration?.coerceAtLeast(0) ?: 0) },
        )
    }

    fun state(playerState: String?): CastState? = when (playerState) {
        "PLAYING" -> CastState.PLAYING
        "PAUSED" -> CastState.PAUSED
        "BUFFERING" -> CastState.LOADING
        "IDLE" -> CastState.STOPPED
        else -> null
    }

    /** 4 for photos, 3 for music and 1 for video: the Cast metadata types. */
    private fun metadataType(mime: String): Int = when (CastKind.of(mime)) {
        CastKind.PHOTO -> 4
        CastKind.MUSIC -> 3
        else -> 1
    }

    private fun message(type: String) = buildJsonObject { put("type", type) }

    private fun request(type: String, requestId: Int) = buildJsonObject {
        put("type", type)
        put("requestId", requestId)
    }

    private fun mediaCall(type: String, requestId: Int, mediaSessionId: Long?) = buildJsonObject {
        put("type", type)
        put("requestId", requestId)
        mediaSessionId?.let { put("mediaSessionId", it) }
    }

    private fun JsonPrimitive.contentOrNullSafe(): String? = if (isString) content else null
}

/** The Default Media Receiver running on a TV: [transportId] is where media messages go. */
data class CastApp(val sessionId: String, val transportId: String)

/** What a Cast TV's player reports. A null [state] means it reported nothing we know. */
data class CastMedia(val mediaSessionId: Long?, val state: CastState?, val position: CastPosition?)

/** One Cast message, as sent over the TLS connection in a 4-byte length frame. Only text payloads are used. */
data class CastMessage(val source: String, val destination: String, val namespace: String, val payload: String) {
    /** The protobuf encoding of the message. */
    fun encode(): ByteArray {
        val out = ByteArrayOutputStream()

        out.write(byteArrayOf(0x08, 0x00))
        writeString(out, 2, source)
        writeString(out, 3, destination)
        writeString(out, 4, namespace)
        out.write(byteArrayOf(0x28, 0x00))
        writeString(out, 6, payload)

        return out.toByteArray()
    }

    companion object {
        /** Reads a message, skipping fields it doesn't use. Null if [bytes] isn't a whole message. */
        fun decode(bytes: ByteArray): CastMessage? {
            val fields = HashMap<Int, String>()
            var at = 0

            fun varint(): Long? {
                var value = 0L
                var shift = 0
                while (at < bytes.size && shift < 64) {
                    val b = bytes[at++].toInt() and 0xff
                    value = value or ((b and 0x7f).toLong() shl shift)
                    if (b and 0x80 == 0) return value
                    shift += 7
                }
                return null
            }

            while (at < bytes.size) {
                val tag = varint() ?: return null
                val field = (tag shr 3).toInt()

                when ((tag and 7).toInt()) {
                    0 -> varint() ?: return null
                    1 -> at += 8
                    2 -> {
                        val length = varint()?.toInt() ?: return null
                        if (length < 0 || at + length > bytes.size) return null
                        fields[field] = String(bytes, at, length, Charsets.UTF_8)
                        at += length
                    }
                    5 -> at += 4
                    else -> return null
                }
            }

            if (at > bytes.size) return null

            return CastMessage(fields[2].orEmpty(), fields[3].orEmpty(), fields[4] ?: return null, fields[6].orEmpty())
        }

        private fun writeString(out: ByteArrayOutputStream, field: Int, text: String) {
            val bytes = text.toByteArray(Charsets.UTF_8)

            out.write(field shl 3 or 2)
            var length = bytes.size
            while (length >= 0x80) {
                out.write(length and 0x7f or 0x80)
                length = length ushr 7
            }
            out.write(length)
            out.write(bytes)
        }
    }
}

/** One record from an mDNS answer. [data] is the target name (PTR), "port target" (SRV), the IPv4 address (A) or key=value lines (TXT). */
data class DnsRecord(val name: String, val type: Int, val data: List<String>)

/** Multicast DNS, which Cast TVs answer to say where they are. */
object Mdns {
    const val ADDRESS = "224.0.0.251"
    const val PORT = 5353

    const val A = 1
    const val PTR = 12
    const val TXT = 16
    const val SRV = 33

    /** A question for [service], asking for answers sent straight back to us. */
    fun query(service: String = GoogleCast.SERVICE): ByteArray {
        val out = ByteArrayOutputStream()

        out.write(byteArrayOf(0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0))
        for (label in service.split('.').filter { it.isNotEmpty() }) {
            val bytes = label.toByteArray(Charsets.UTF_8)
            out.write(bytes.size)
            out.write(bytes)
        }
        out.write(byteArrayOf(0, 0, PTR.toByte(), 0x80.toByte(), 0x01))

        return out.toByteArray()
    }

    /** The answer, authority and additional records in [packet]. Empty if it's malformed or a question. */
    fun parse(packet: ByteArray): List<DnsRecord> = runCatching {
        val reader = Reader(packet)
        val flags = reader.u16(2)
        if (flags and 0x8000 == 0) return emptyList()

        val questions = reader.u16(4)
        val records = reader.u16(6) + reader.u16(8) + reader.u16(10)

        reader.at = 12
        repeat(questions) {
            reader.name()
            reader.at += 4
        }

        List(records) { reader.record() }.filterNotNull()
    }.getOrDefault(emptyList())

    /** The Cast TVs in a set of records. [sender] is used when there is no address record. */
    fun castTvs(records: List<DnsRecord>, sender: String): List<TvRenderer> {
        val service = GoogleCast.SERVICE.lowercase()

        return records.filter { it.type == PTR && it.name.lowercase() == service }.mapNotNull { pointer ->
            val instance = pointer.data.firstOrNull() ?: return@mapNotNull null
            val srv = records.firstOrNull { it.type == SRV && it.name.equals(instance, ignoreCase = true) }?.data?.firstOrNull()?.split(' ', limit = 2)
            val txt = records.firstOrNull { it.type == TXT && it.name.equals(instance, ignoreCase = true) }?.data.orEmpty()
                .mapNotNull { line -> line.indexOf('=').takeIf { it > 0 }?.let { line.substring(0, it).lowercase() to line.substring(it + 1) } }
                .toMap()

            val port = srv?.firstOrNull()?.toIntOrNull() ?: GoogleCast.PORT
            val host = srv?.getOrNull(1)?.let { target -> records.firstOrNull { it.type == A && it.name.equals(target, ignoreCase = true) }?.data?.firstOrNull() } ?: sender

            TvRenderer(
                id = "cast:" + (txt["id"] ?: instance),
                name = txt["fn"]?.takeIf { it.isNotBlank() } ?: instance.substringBefore('.'),
                cast = CastEndpoint(host, port),
            )
        }
    }

    private class Reader(val bytes: ByteArray) {
        var at = 0

        fun u8(offset: Int): Int = bytes[offset].toInt() and 0xff

        fun u16(offset: Int): Int = u8(offset) shl 8 or u8(offset + 1)

        fun record(): DnsRecord? {
            val name = name()
            val type = u16(at)
            val length = u16(at + 8)
            val start = at + 10
            val end = start + length
            if (end > bytes.size) throw IndexOutOfBoundsException()

            at = start
            val data = when (type) {
                PTR -> listOf(name())
                SRV -> {
                    val port = u16(start + 4)
                    at = start + 6
                    listOf("$port ${name()}")
                }
                A -> if (length == 4) listOf((0 until 4).joinToString(".") { u8(start + it).toString() }) else null
                TXT -> buildList {
                    var i = start
                    while (i < end) {
                        val size = u8(i)
                        if (i + 1 + size > end) break
                        add(String(bytes, i + 1, size, Charsets.UTF_8))
                        i += 1 + size
                    }
                }
                else -> null
            }
            at = end

            return data?.let { DnsRecord(name, type, it) }
        }

        /** Reads a name at [at], following compression pointers. */
        fun name(): String {
            val labels = mutableListOf<String>()
            var offset = at
            var jumped = false
            var jumps = 0

            while (true) {
                val size = u8(offset)
                when {
                    size == 0 -> {
                        if (!jumped) at = offset + 1
                        return labels.joinToString(".")
                    }
                    size and 0xc0 == 0xc0 -> {
                        if (++jumps > 16) throw IllegalStateException("name loops")
                        if (!jumped) at = offset + 2
                        offset = (size and 0x3f) shl 8 or u8(offset + 1)
                        jumped = true
                    }
                    else -> {
                        labels += String(bytes, offset + 1, size, Charsets.UTF_8)
                        offset += 1 + size
                    }
                }
            }
        }
    }
}
