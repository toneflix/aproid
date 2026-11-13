package com.toneflix.aproid.protocol

/**
 * Call audio on the Mac. Android doesn't let apps carry call audio, so the Mac joins the phone as a
 * Bluetooth hands-free device instead. These packets pair the two and report how the link stands.
 */
object CallAudio {
    enum class Action(val wire: String) {
        STATUS("status"),
        PAIR("pair");

        companion object {
            fun fromWire(wire: String?): Action? = entries.firstOrNull { it.wire == wire }
        }
    }

    /** [address] is the Mac's Bluetooth address, as "AA:BB:CC:DD:EE:FF". */
    data class Request(val action: Action, val address: String, val name: String? = null)

    /** [name] is the phone's Bluetooth name. [allowed] is false until the user lets FlyyLink use Bluetooth. */
    data class Status(
        val bluetoothOn: Boolean,
        val allowed: Boolean,
        val paired: Boolean,
        val connected: Boolean,
        val name: String? = null,
    )

    fun request(request: Request): NetworkPacket = NetworkPacket(
        PacketType.CALL_AUDIO_REQUEST,
        NetworkPacket.body("action" to request.action.wire, "address" to request.address, "name" to request.name),
    )

    fun request(packet: NetworkPacket): Request? {
        if (packet.type != PacketType.CALL_AUDIO_REQUEST) return null

        val action = Action.fromWire(packet.string("action")) ?: return null
        val address = normalizeAddress(packet.string("address")) ?: return null

        return Request(action, address, packet.string("name")?.takeIf { it.isNotBlank() })
    }

    fun status(status: Status): NetworkPacket = NetworkPacket(
        PacketType.CALL_AUDIO,
        NetworkPacket.body(
            "bluetoothOn" to status.bluetoothOn,
            "allowed" to status.allowed,
            "paired" to status.paired,
            "connected" to status.connected,
            "name" to status.name,
        ),
    )

    fun status(packet: NetworkPacket): Status? {
        if (packet.type != PacketType.CALL_AUDIO) return null

        return Status(
            bluetoothOn = packet.bool("bluetoothOn") == true,
            allowed = packet.bool("allowed") == true,
            paired = packet.bool("paired") == true,
            connected = packet.bool("connected") == true,
            name = packet.string("name")?.takeIf { it.isNotBlank() },
        )
    }

    /** Turns "aa-bb-cc-dd-ee-ff", "aabbccddeeff" or "AA:BB:CC:DD:EE:FF" into the last form, or null if it isn't an address. */
    fun normalizeAddress(raw: String?): String? {
        val hex = raw?.filter { it.isLetterOrDigit() }?.uppercase() ?: return null
        if (hex.length != 12 || !hex.all { it in '0'..'9' || it in 'A'..'F' }) return null

        return hex.chunked(2).joinToString(":")
    }
}
