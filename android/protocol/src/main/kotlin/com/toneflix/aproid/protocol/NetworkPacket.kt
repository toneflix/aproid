package com.toneflix.aproid.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

class ProtocolException(message: String) : Exception(message)

/**
 * One KDE Connect packet. On the wire it is a single line of JSON ending in "\n".
 */
data class NetworkPacket(
    val type: String,
    val body: JsonObject = JsonObject(emptyMap()),
    val id: Long = System.currentTimeMillis(),
    val payloadSize: Long? = null,
    val payloadTransferInfo: JsonObject? = null,
) {
    fun serialize(): String {
        val obj = buildJsonObject {
            put("id", JsonPrimitive(id))
            put("type", JsonPrimitive(type))
            put("body", body)
            payloadSize?.let { put("payloadSize", JsonPrimitive(it)) }
            payloadTransferInfo?.let { put("payloadTransferInfo", it) }
        }
        return obj.toString() + "\n"
    }

    fun string(key: String): String? = (body[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    fun int(key: String): Int? = (body[key] as? JsonPrimitive)?.intOrNull
    fun long(key: String): Long? = (body[key] as? JsonPrimitive)?.longOrNull
    fun bool(key: String): Boolean? = (body[key] as? JsonPrimitive)?.booleanOrNull

    /** The port the sender opened for this packet's payload. */
    val payloadPort: Int? get() = (payloadTransferInfo?.get("port") as? JsonPrimitive)?.intOrNull
    fun stringList(key: String): List<String> =
        (body[key] as? kotlinx.serialization.json.JsonArray)
            ?.mapNotNull { (it as? JsonPrimitive)?.content }
            ?: emptyList()

    companion object {
        fun parse(line: String): NetworkPacket {
            val root: JsonElement = try {
                Json.parseToJsonElement(line.trim())
            } catch (e: Exception) {
                throw ProtocolException("invalid JSON: ${e.message}")
            }
            val obj = root as? JsonObject ?: throw ProtocolException("packet is not an object")
            val type = (obj["type"] as? JsonPrimitive)?.content ?: throw ProtocolException("missing type")
            // Some older clients send the id as a string.
            val idPrim = obj["id"] as? JsonPrimitive
            val id = idPrim?.longOrNull ?: idPrim?.content?.toLongOrNull() ?: 0L
            val body = (obj["body"] as? JsonObject) ?: JsonObject(emptyMap())
            val payloadSize = (obj["payloadSize"] as? JsonPrimitive)?.longOrNull
            val transferInfo = obj["payloadTransferInfo"]?.let { it as? JsonObject }
            return NetworkPacket(type, body, id, payloadSize, transferInfo)
        }

        fun body(vararg pairs: Pair<String, Any?>): JsonObject = buildJsonObject {
            for ((k, v) in pairs) {
                when (v) {
                    null -> {}
                    is String -> put(k, JsonPrimitive(v))
                    is Number -> put(k, JsonPrimitive(v))
                    is Boolean -> put(k, JsonPrimitive(v))
                    is JsonElement -> put(k, v)
                    is Collection<*> -> put(k, kotlinx.serialization.json.JsonArray(v.map { JsonPrimitive(it.toString()) }))
                    else -> throw IllegalArgumentException("unsupported body value for $k")
                }
            }
        }
    }
}
