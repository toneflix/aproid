package com.toneflix.aproid.protocol

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * A phone's packets passed on by one computer to another that isn't connected to that phone ("aproid.relay").
 * The computer next to the phone wraps what the phone sends, such as notifications and calls. The other computer
 * wraps its answers, such as replies and call buttons, and the first one hands them to the phone. Payloads are not
 * relayed. Phones never send or receive these; the protocol is here to keep the three copies in step.
 */
object Relay {
    /** What a computer passes on from a phone. */
    val FROM_PHONE: Set<String> = setOf(PacketType.NOTIFICATION, PacketType.TELEPHONY)

    /** What a computer passes on to a phone. */
    val TO_PHONE: Set<String> = setOf(
        PacketType.NOTIFICATION_REQUEST,
        PacketType.NOTIFICATION_REPLY,
        PacketType.NOTIFICATION_ACTION,
        PacketType.CALL_REQUEST,
    )

    data class Message(val phoneId: String, val phoneName: String, val packet: NetworkPacket)

    fun wrap(packet: NetworkPacket, phoneId: String, phoneName: String): NetworkPacket = NetworkPacket(
        PacketType.RELAY,
        buildJsonObject {
            put("phoneId", JsonPrimitive(phoneId))
            put("phoneName", JsonPrimitive(phoneName))
            put("packet", buildJsonObject {
                put("type", JsonPrimitive(packet.type))
                put("body", packet.body)
            })
        },
    )

    /** The wrapped packet, or null when it isn't one that may be relayed. */
    fun message(packet: NetworkPacket): Message? {
        if (packet.type != PacketType.RELAY) return null

        val phoneId = packet.string("phoneId")?.takeIf { it.isNotEmpty() } ?: return null
        val inner = packet.body["packet"] as? JsonObject ?: return null
        val type = (inner["type"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        if (type !in FROM_PHONE && type !in TO_PHONE) return null

        val body = inner["body"] as? JsonObject ?: JsonObject(emptyMap())
        val name = packet.string("phoneName")?.takeIf { it.isNotEmpty() } ?: "Phone"
        return Message(phoneId, name, NetworkPacket(type, body, packet.id))
    }
}
