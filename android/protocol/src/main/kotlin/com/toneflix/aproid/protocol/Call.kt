package com.toneflix.aproid.protocol

/** What a "kdeconnect.telephony" packet reports about a call. */
enum class CallEvent(val wire: String) {
    RINGING("ringing"),
    TALKING("talking"),
    MISSED("missedCall");

    companion object {
        fun fromWire(wire: String?): CallEvent? = entries.firstOrNull { it.wire == wire }
    }
}

/** Calls: the phone reports them with "kdeconnect.telephony", and the Mac controls them with "aproid.call.request". */
object Call {
    enum class Action(val wire: String) {
        ANSWER("answer"),
        DECLINE("decline"),
        HANG_UP("hangUp"),
        MUTE("mute"),
        UNMUTE("unmute"),
        DIAL("dial");

        companion object {
            fun fromWire(wire: String?): Action? = entries.firstOrNull { it.wire == wire }
        }
    }

    data class Request(val action: Action, val number: String? = null)

    /** [photo] is the caller's contact photo as base64 JPEG. [ended] means the call is over. */
    data class State(val event: CallEvent, val number: String, val contactName: String?, val photo: String?, val ended: Boolean)

    fun event(event: CallEvent, number: String, contactName: String? = null, photo: String? = null): NetworkPacket = NetworkPacket(
        PacketType.TELEPHONY,
        NetworkPacket.body("event" to event.wire, "phoneNumber" to number, "contactName" to contactName, "phoneThumbnail" to photo),
    )

    fun ended(number: String): NetworkPacket = NetworkPacket(
        PacketType.TELEPHONY,
        NetworkPacket.body("event" to CallEvent.RINGING.wire, "phoneNumber" to number, "isCancel" to true),
    )

    fun state(packet: NetworkPacket): State? {
        if (packet.type != PacketType.TELEPHONY) return null

        val event = CallEvent.fromWire(packet.string("event")) ?: return null
        return State(
            event = event,
            number = packet.string("phoneNumber").orEmpty(),
            contactName = packet.string("contactName")?.takeIf { it.isNotEmpty() },
            photo = packet.string("phoneThumbnail")?.takeIf { it.isNotEmpty() },
            ended = packet.bool("isCancel") == true,
        )
    }

    fun answer(): NetworkPacket = request(Request(Action.ANSWER))

    fun decline(): NetworkPacket = request(Request(Action.DECLINE))

    fun hangUp(): NetworkPacket = request(Request(Action.HANG_UP))

    fun mute(muted: Boolean): NetworkPacket = request(Request(if (muted) Action.MUTE else Action.UNMUTE))

    fun dial(number: String): NetworkPacket = request(Request(Action.DIAL, number))

    fun request(request: Request): NetworkPacket =
        NetworkPacket(PacketType.CALL_REQUEST, NetworkPacket.body("action" to request.action.wire, "number" to request.number))

    fun request(packet: NetworkPacket): Request? {
        if (packet.type != PacketType.CALL_REQUEST) return null

        val action = Action.fromWire(packet.string("action")) ?: return null
        val number = packet.string("number")?.takeIf { it.isNotBlank() }
        if (action == Action.DIAL && number == null) return null

        return Request(action, number)
    }
}
