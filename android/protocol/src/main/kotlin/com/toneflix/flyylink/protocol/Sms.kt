package com.toneflix.flyylink.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** A phone number or email a message went to or came from. [name] is the phone's contact name, if any. */
data class SmsAddress(val address: String, val name: String? = null)

/** A picture or file in an MMS. [thumbnail] is a small base64 JPEG. */
data class SmsAttachment(val partId: Long, val mimeType: String, val uniqueId: String, val thumbnail: String? = null)

/** One text or MMS, in the shape of KDE Connect's "kdeconnect.sms.messages". */
data class SmsMessage(
    val id: Long,
    val threadId: Long,
    val body: String,
    val addresses: List<SmsAddress>,
    val date: Long,
    val isIncoming: Boolean,
    val isRead: Boolean = true,
    val subscriptionId: Int? = null,
    val attachments: List<SmsAttachment> = emptyList(),
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("_id", id)
        put("thread_id", threadId)
        put("body", body)
        put("date", date)
        put("type", if (isIncoming) TYPE_INBOX else TYPE_SENT)
        put("read", if (isRead) 1 else 0)
        put("event", if (addresses.size > 1) EVENT_MULTI_TARGET else EVENT_TEXT)
        subscriptionId?.let { put("sub_id", it) }
        put("addresses", buildJsonArray {
            addresses.forEach { address ->
                add(buildJsonObject {
                    put("address", address.address)
                    address.name?.let { put("name", it) }
                })
            }
        })
        if (attachments.isNotEmpty()) {
            put("attachments", buildJsonArray {
                attachments.forEach { attachment ->
                    add(buildJsonObject {
                        put("part_id", attachment.partId)
                        put("mime_type", attachment.mimeType)
                        put("unique_identifier", attachment.uniqueId)
                        attachment.thumbnail?.let { put("encoded_thumbnail", it) }
                    })
                }
            })
        }
    }

    companion object {
        const val TYPE_INBOX = 1
        const val TYPE_SENT = 2
        private const val EVENT_TEXT = 1
        private const val EVENT_MULTI_TARGET = 2

        fun fromJson(json: JsonObject): SmsMessage? {
            val id = json.long("_id") ?: return null
            val threadId = json.long("thread_id") ?: return null

            return SmsMessage(
                id = id,
                threadId = threadId,
                body = json.string("body").orEmpty(),
                addresses = (json["addresses"] as? JsonArray).orEmpty().mapNotNull { item ->
                    val address = (item as? JsonObject)?.string("address") ?: return@mapNotNull null
                    SmsAddress(address, item.string("name"))
                },
                date = json.long("date") ?: 0,
                isIncoming = json.int("type") != TYPE_SENT,
                isRead = json.int("read")?.let { it != 0 } ?: json.bool("read") ?: true,
                subscriptionId = json.int("sub_id"),
                attachments = (json["attachments"] as? JsonArray).orEmpty().mapNotNull { item ->
                    val part = item as? JsonObject ?: return@mapNotNull null
                    SmsAttachment(
                        partId = part.long("part_id") ?: return@mapNotNull null,
                        mimeType = part.string("mime_type").orEmpty(),
                        uniqueId = part.string("unique_identifier").orEmpty(),
                        thumbnail = part.string("encoded_thumbnail"),
                    )
                },
            )
        }
    }
}

/** The SMS packets: message lists from the phone, and what the Mac asks for. */
object Sms {
    data class ConversationRequest(val threadId: Long, val before: Long?, val count: Int?)

    data class SendRequest(val addresses: List<String>, val body: String, val subscriptionId: Int?)

    fun messagesPacket(messages: List<SmsMessage>): NetworkPacket = NetworkPacket(
        PacketType.SMS_MESSAGES,
        buildJsonObject {
            put("version", 2)
            put("messages", JsonArray(messages.map { it.toJson() }))
        },
    )

    fun messages(packet: NetworkPacket): List<SmsMessage>? {
        if (packet.type != PacketType.SMS_MESSAGES) return null

        return (packet.body["messages"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(SmsMessage::fromJson) }
    }

    /** Asks for the newest message of every conversation. */
    fun requestConversations(): NetworkPacket = NetworkPacket(PacketType.SMS_REQUEST_CONVERSATIONS, NetworkPacket.body())

    /** Asks for up to [count] messages of one conversation, older than [before] when set. */
    fun requestConversation(threadId: Long, before: Long? = null, count: Int = 50): NetworkPacket = NetworkPacket(
        PacketType.SMS_REQUEST_CONVERSATION,
        NetworkPacket.body("threadID" to threadId, "rangeStartTimestamp" to before, "numberToRequest" to count),
    )

    fun conversationRequest(packet: NetworkPacket): ConversationRequest? {
        if (packet.type != PacketType.SMS_REQUEST_CONVERSATION) return null

        val threadId = packet.long("threadID") ?: return null
        return ConversationRequest(threadId, packet.long("rangeStartTimestamp")?.takeIf { it > 0 }, packet.int("numberToRequest"))
    }

    fun send(addresses: List<String>, body: String, subscriptionId: Int? = null): NetworkPacket = NetworkPacket(
        PacketType.SMS_REQUEST,
        buildJsonObject {
            put("version", 2)
            put("messageBody", body)
            put("addresses", buildJsonArray { addresses.forEach { add(buildJsonObject { put("address", it) }) } })
            subscriptionId?.let { put("subID", it) }
        },
    )

    fun sendRequest(packet: NetworkPacket): SendRequest? {
        if (packet.type != PacketType.SMS_REQUEST) return null

        val body = packet.string("messageBody") ?: return null
        // Version 1 sent a single "phoneNumber".
        val addresses = (packet.body["addresses"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.string("address") }
            ?: listOfNotNull(packet.string("phoneNumber"))
        if (addresses.isEmpty()) return null

        return SendRequest(addresses, body, packet.int("subID"))
    }
}

private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
private fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.let { it.longOrNull ?: it.content.toLongOrNull() }
private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.let { it.intOrNull ?: it.content.toIntOrNull() }
private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
private fun JsonArray?.orEmpty(): List<kotlinx.serialization.json.JsonElement> = this ?: emptyList()
