package com.toneflix.aproid.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** One photo or video in the phone's gallery. [date] is when it was taken, in milliseconds; [thumbnail] is base64 JPEG. */
data class PhonePhoto(
    val id: Long,
    val name: String,
    val date: Long,
    val mimeType: String,
    val width: Int = 0,
    val height: Int = 0,
    val size: Long = 0,
    val thumbnail: String? = null,
) {
    val isVideo: Boolean get() = mimeType.startsWith("video/")

    fun toJson(): JsonObject = buildJsonObject {
        put("id", id)
        put("name", name)
        put("date", date)
        put("mimeType", mimeType)
        put("width", width)
        put("height", height)
        put("size", size)
        thumbnail?.let { put("thumbnail", it) }
    }

    companion object {
        fun fromJson(json: JsonObject): PhonePhoto? {
            fun primitive(key: String) = json[key] as? JsonPrimitive
            val id = primitive("id")?.longOrNull ?: return null

            return PhonePhoto(
                id = id,
                name = primitive("name")?.content.orEmpty(),
                date = primitive("date")?.longOrNull ?: 0,
                mimeType = primitive("mimeType")?.content ?: "image/jpeg",
                width = primitive("width")?.intOrNull ?: 0,
                height = primitive("height")?.intOrNull ?: 0,
                size = primitive("size")?.longOrNull ?: 0,
                thumbnail = primitive("thumbnail")?.takeIf { it.isString }?.content,
            )
        }
    }
}

/** Browsing the phone's gallery from the Mac. Full photos come back as normal shared files. */
object Photos {
    const val PAGE = 40

    data class Request(val before: Long?, val count: Int)

    data class Page(val photos: List<PhonePhoto>, val more: Boolean)

    fun request(before: Long? = null, count: Int = PAGE): NetworkPacket =
        NetworkPacket(PacketType.PHOTOS_REQUEST, NetworkPacket.body("before" to before, "count" to count))

    fun request(packet: NetworkPacket): Request? {
        if (packet.type != PacketType.PHOTOS_REQUEST) return null

        return Request(packet.long("before")?.takeIf { it > 0 }, (packet.int("count") ?: PAGE).coerceIn(1, 200))
    }

    fun pagePacket(photos: List<PhonePhoto>, more: Boolean): NetworkPacket = NetworkPacket(
        PacketType.PHOTOS,
        buildJsonObject {
            put("photos", JsonArray(photos.map { it.toJson() }))
            put("more", more)
        },
    )

    fun page(packet: NetworkPacket): Page? {
        if (packet.type != PacketType.PHOTOS) return null

        val photos = (packet.body["photos"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(PhonePhoto::fromJson) }
        return Page(photos, (packet.body["more"] as? JsonPrimitive)?.booleanOrNull ?: false)
    }

    fun download(id: Long): NetworkPacket = NetworkPacket(PacketType.PHOTOS_DOWNLOAD, NetworkPacket.body("id" to id))

    fun downloadId(packet: NetworkPacket): Long? =
        if (packet.type == PacketType.PHOTOS_DOWNLOAD) packet.long("id") else null
}
