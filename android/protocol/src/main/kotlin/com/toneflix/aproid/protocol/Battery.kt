package com.toneflix.aproid.protocol

/** The phone's battery ("kdeconnect.battery"). */
data class BatteryStatus(
    val charge: Int,
    val isCharging: Boolean,
    val isLow: Boolean = false,
) {
    fun toPacket(): NetworkPacket = NetworkPacket(
        type = PacketType.BATTERY,
        body = NetworkPacket.body(
            "currentCharge" to charge,
            "isCharging" to isCharging,
            "thresholdEvent" to if (isLow) THRESHOLD_LOW else THRESHOLD_NONE,
        ),
    )

    companion object {
        private const val THRESHOLD_NONE = 0
        private const val THRESHOLD_LOW = 1

        /** At or below this level, and not charging, the battery counts as low. */
        const val LOW_LEVEL = 15

        fun of(charge: Int, isCharging: Boolean) =
            BatteryStatus(charge, isCharging, isLow = !isCharging && charge <= LOW_LEVEL)

        fun fromPacket(packet: NetworkPacket): BatteryStatus? {
            if (packet.type != PacketType.BATTERY) return null

            val charge = packet.int("currentCharge") ?: return null

            return BatteryStatus(
                charge = charge,
                isCharging = packet.bool("isCharging") ?: false,
                isLow = packet.int("thresholdEvent") == THRESHOLD_LOW,
            )
        }

        fun request(): NetworkPacket =
            NetworkPacket(PacketType.BATTERY_REQUEST, NetworkPacket.body("request" to true))
    }
}
