package com.toneflix.aproid.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.longOrNull
import java.util.UUID

/** Lets some packets pass to and from a device that is not paired. [Device] asks before delivering or sending one. */
interface GuestAccess {
    /** True when [packet] from the unpaired [deviceId] may reach the plugins. */
    fun admitsIncoming(deviceId: String, packet: NetworkPacket): Boolean

    /** True when [packet] may go to the unpaired [deviceId]. */
    fun admitsOutgoing(deviceId: String, packet: NetworkPacket): Boolean
}

/**
 * FlyyDrop: AirDrop-style sharing with any nearby FlyyLink device, paired or not.
 *
 * The sender asks first with "flyylink.flyydrop.request", listing the files or the link or text. The receiver's user
 * accepts or declines ("flyylink.flyydrop.response"), and only then do the items arrive as ordinary
 * "kdeconnect.share.request" packets tagged with the request's id. An unpaired device gets nothing more: as its
 * [GuestAccess], this class lets in exactly the accepted items, once each. Mirrors FlyyDrop.swift and FlyyDrop.cs.
 */
class FlyyDrop(private val clock: () -> Long = System::currentTimeMillis) : GuestAccess {
    /** Who may send this device a request without being paired. */
    enum class Receiving { OFF, EVERYONE_FOR_10_MINUTES, EVERYONE }

    /** Why a request was turned down. */
    enum class Reason(val wire: String) {
        DECLINED("declined"),
        UNAVAILABLE("unavailable"),
        BUSY("busy");

        companion object {
            fun fromWire(value: String?): Reason = entries.firstOrNull { it.wire == value } ?: DECLINED
        }
    }

    data class Item(val name: String, val size: Long) {
        val safeName: String get() = Share.File(name, size).safeName
    }

    /** One request: files, or a link or some text, between this device and [deviceId]. */
    data class Offer(val id: String, val deviceId: String, val items: List<Item>, val text: String? = null) {
        val totalSize: Long get() = items.sumOf { it.size }
    }

    /** What to do with a request that arrived: ask the user, or send [packet] straight back. */
    sealed interface Incoming {
        data class Ask(val offer: Offer) : Incoming

        data class Reply(val packet: NetworkPacket) : Incoming
    }

    /** The receiver's answer to one of our requests. */
    data class Answer(val offer: Offer, val accepted: Boolean, val reason: Reason?)

    private enum class Stage { ASKING, ACCEPTED }

    private class Transfer(val offer: Offer, var stage: Stage, var expires: Long) {
        val waiting = offer.items.toMutableList()
        var textWaiting = offer.text != null

        val isDone: Boolean get() = waiting.isEmpty() && !textWaiting

        fun matches(deviceId: String, stage: Stage) = offer.deviceId == deviceId && this.stage == stage
    }

    private val incoming = mutableMapOf<String, Transfer>()
    private val outgoing = mutableMapOf<String, Transfer>()
    private var mode = Receiving.OFF
    private var everyoneUntil = 0L

    /** Who may send a request now. "Everyone for 10 minutes" reads as off once the time is up. */
    var receiving: Receiving
        @Synchronized get() = if (mode == Receiving.EVERYONE_FOR_10_MINUTES && clock() >= everyoneUntil) Receiving.OFF else mode
        @Synchronized set(value) {
            mode = value
            everyoneUntil = clock() + EVERYONE_MS
        }

    /** When "Everyone for 10 minutes" ends, in milliseconds, or null for the other settings. */
    val receivingUntil: Long?
        @Synchronized get() = everyoneUntil.takeIf { receiving == Receiving.EVERYONE_FOR_10_MINUTES }

    /** Puts back a setting saved earlier, keeping its original end time. */
    @Synchronized fun restore(mode: Receiving, until: Long?) {
        this.mode = mode
        everyoneUntil = until ?: 0
    }

    // Sending

    /** Starts a request to [deviceId]. Send the returned packet, then wait for [onResponse]. */
    @Synchronized fun request(deviceId: String, items: List<Item>, text: String? = null): NetworkPacket {
        require(items.isNotEmpty() || !text.isNullOrEmpty()) { "nothing to send" }

        val offer = Offer(UUID.randomUUID().toString(), deviceId, items, text?.takeIf { it.isNotEmpty() })
        outgoing[offer.id] = Transfer(offer, Stage.ASKING, clock() + ASK_MS + GRACE_MS)

        return requestPacket(offer)
    }

    /** Reads the receiver's answer to one of our requests. */
    @Synchronized fun onResponse(deviceId: String, packet: NetworkPacket): Answer? {
        if (packet.type != PacketType.FLYYDROP_RESPONSE) return null

        val id = packet.string("id") ?: return null
        val transfer = outgoing[id]?.takeIf { it.matches(deviceId, Stage.ASKING) } ?: return null
        val accepted = packet.bool("accept") == true

        if (accepted) {
            transfer.stage = Stage.ACCEPTED
            transfer.expires = clock() + ACCEPTED_MS
        } else {
            outgoing.remove(id)
        }

        return Answer(transfer.offer, accepted, if (accepted) null else Reason.fromWire(packet.string("reason")))
    }

    // Receiving

    /** Decides what to do with a request from [deviceId]. Returns null for a malformed or repeated one. */
    @Synchronized fun onRequest(deviceId: String, packet: NetworkPacket, isPaired: Boolean): Incoming? {
        val offer = offer(deviceId, packet) ?: return null
        if (incoming.containsKey(offer.id)) return null

        if (!isPaired && receiving == Receiving.OFF) return Incoming.Reply(response(offer.id, Reason.UNAVAILABLE))

        val asking = incoming.values.filter { it.stage == Stage.ASKING }
        if (asking.size >= MAX_ASKING || asking.any { it.offer.deviceId == deviceId }) {
            return Incoming.Reply(response(offer.id, Reason.BUSY))
        }

        incoming[offer.id] = Transfer(offer, Stage.ASKING, clock() + ASK_MS)

        return Incoming.Ask(offer)
    }

    /** The user accepted. Send the returned packet; the items may then come in. */
    @Synchronized fun accept(id: String): NetworkPacket? {
        val transfer = incoming[id]?.takeIf { it.stage == Stage.ASKING } ?: return null

        transfer.stage = Stage.ACCEPTED
        transfer.expires = clock() + ACCEPTED_MS

        return NetworkPacket(PacketType.FLYYDROP_RESPONSE, NetworkPacket.body("id" to id, "accept" to true))
    }

    /** The user declined. Send the returned packet. */
    @Synchronized fun decline(id: String): NetworkPacket? {
        incoming.remove(id) ?: return null

        return response(id, Reason.DECLINED)
    }

    // Either side

    /** Stops a request in either direction. Send the returned packet to tell the other device. */
    @Synchronized fun cancel(id: String): NetworkPacket? {
        (incoming.remove(id) ?: outgoing.remove(id)) ?: return null

        return NetworkPacket(PacketType.FLYYDROP_CANCEL, NetworkPacket.body("id" to id))
    }

    /** The other device stopped a request. Returns it, so its prompt or progress can go away. */
    @Synchronized fun onCancel(deviceId: String, packet: NetworkPacket): Offer? {
        if (packet.type != PacketType.FLYYDROP_CANCEL) return null

        val id = packet.string("id") ?: return null
        val map = listOf(incoming, outgoing).firstOrNull { it[id]?.offer?.deviceId == deviceId } ?: return null

        return map.remove(id)?.offer
    }

    /** Forgets requests nobody answered and accepted ones that went quiet, and returns them. Call every few seconds. */
    @Synchronized fun expire(): List<Offer> {
        val now = clock()
        val expired = (incoming.values + outgoing.values).filter { it.expires <= now }.map { it.offer }

        incoming.values.removeAll { it.expires <= now }
        outgoing.values.removeAll { it.expires <= now }

        return expired
    }

    /** True while [id] is waiting for an answer or still has items to move. */
    @Synchronized fun isActive(id: String): Boolean = incoming.containsKey(id) || outgoing.containsKey(id)

    // GuestAccess

    @Synchronized override fun admitsIncoming(deviceId: String, packet: NetworkPacket): Boolean = when (packet.type) {
        PacketType.FLYYDROP_REQUEST, PacketType.FLYYDROP_CANCEL -> true
        PacketType.FLYYDROP_RESPONSE -> packet.string("id")?.let { outgoing[it] }?.matches(deviceId, Stage.ASKING) == true
        PacketType.SHARE_REQUEST -> take(incoming, deviceId, packet, size = packet.payloadSize)
        else -> false
    }

    @Synchronized override fun admitsOutgoing(deviceId: String, packet: NetworkPacket): Boolean = when (packet.type) {
        PacketType.FLYYDROP_REQUEST -> packet.string("id")?.let { outgoing[it] }?.matches(deviceId, Stage.ASKING) == true
        PacketType.FLYYDROP_CANCEL -> true
        PacketType.FLYYDROP_RESPONSE ->
            packet.bool("accept") != true || packet.string("id")?.let { incoming[it] }?.matches(deviceId, Stage.ACCEPTED) == true
        PacketType.SHARE_REQUEST -> take(outgoing, deviceId, packet, size = packet.long("totalPayloadSize"))
        else -> false
    }

    /** Lets one accepted item through, once, and forgets the request after its last item. */
    private fun take(transfers: MutableMap<String, Transfer>, deviceId: String, packet: NetworkPacket, size: Long?): Boolean {
        val id = packet.string(TAG) ?: return false
        val transfer = transfers[id]?.takeIf { it.matches(deviceId, Stage.ACCEPTED) } ?: return false

        val name = packet.string("filename")
        val text = packet.string("url") ?: packet.string("text")
        val admitted = when {
            name != null -> (packet.long("flyylink.offset") ?: 0) == 0L && transfer.waiting.remove(Item(name, size ?: -1))
            text != null && transfer.textWaiting && text == transfer.offer.text -> true.also { transfer.textWaiting = false }
            else -> false
        }
        if (!admitted) return false

        if (transfer.isDone) transfers.remove(id) else transfer.expires = clock() + ACCEPTED_MS

        return true
    }

    companion object {
        /** How long a request waits for the user to answer. */
        const val ASK_MS = 60_000L

        /** How long an accepted request waits for its next item. */
        const val ACCEPTED_MS = 60 * 60_000L

        /** How long "Everyone for 10 minutes" lasts. */
        const val EVERYONE_MS = 10 * 60_000L

        /** Requests waiting for an answer at once, from all devices. */
        const val MAX_ASKING = 3

        const val MAX_ITEMS = 1000
        const val MAX_TEXT = 64 * 1024

        /** The share packet field that says which request an item belongs to. */
        const val TAG = "flyylink.flyydrop"

        /** The sender waits a little longer than the receiver, so the receiver's answer always wins. */
        private const val GRACE_MS = 5_000L

        /** A file of an accepted request. Send it with [Device.sendWithPayload]. */
        fun file(id: String, item: Item): NetworkPacket = tag(Share.file(item.name, item.size), id)

        /** The link or text of an accepted request. */
        fun text(id: String, text: String): NetworkPacket {
            val isLink = Regex("^https?://\\S+$", RegexOption.IGNORE_CASE).matches(text)

            return tag(if (isLink) Share.link(text) else Share.text(text), id)
        }

        /** The request an item belongs to, or null for an ordinary share. */
        fun requestId(packet: NetworkPacket): String? = packet.string(TAG)

        fun requestPacket(offer: Offer): NetworkPacket = NetworkPacket(
            PacketType.FLYYDROP_REQUEST,
            NetworkPacket.body(
                "id" to offer.id,
                "files" to buildJsonArray {
                    offer.items.forEach { item ->
                        add(buildJsonObject {
                            put("name", JsonPrimitive(item.name))
                            put("size", JsonPrimitive(item.size))
                        })
                    }
                },
                "text" to offer.text,
            ),
        )

        /** Reads a request, or null when it is malformed or too big. */
        fun offer(deviceId: String, packet: NetworkPacket): Offer? {
            if (packet.type != PacketType.FLYYDROP_REQUEST) return null

            val id = packet.string("id")?.takeIf { it.isNotEmpty() && it.length <= 64 } ?: return null
            val files = packet.body["files"] as? JsonArray ?: JsonArray(emptyList())
            if (files.size > MAX_ITEMS) return null

            val items = files.map { element ->
                val json = element as? JsonObject ?: return null
                val name = (json["name"] as? JsonPrimitive)?.takeIf { it.isString }?.content?.takeIf { it.isNotBlank() } ?: return null
                val size = (json["size"] as? JsonPrimitive)?.longOrNull?.takeIf { it >= 0 } ?: return null
                Item(name, size)
            }
            val text = packet.string("text")?.takeIf { it.isNotEmpty() }
            if (text != null && text.length > MAX_TEXT) return null
            if (items.isEmpty() && text == null) return null

            return Offer(id, deviceId, items, text)
        }

        private fun response(id: String, reason: Reason) = NetworkPacket(
            PacketType.FLYYDROP_RESPONSE,
            NetworkPacket.body("id" to id, "accept" to false, "reason" to reason.wire),
        )

        private fun tag(packet: NetworkPacket, id: String) =
            packet.copy(body = JsonObject(packet.body + (TAG to JsonPrimitive(id))))
    }
}
