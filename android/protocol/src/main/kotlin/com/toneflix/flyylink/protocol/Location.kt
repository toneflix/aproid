package com.toneflix.flyylink.protocol

/** Where the phone is, for finding it on the Mac's map. [accuracy] is in metres, [time] in milliseconds. */
data class PhoneLocation(val latitude: Double, val longitude: Double, val accuracy: Double, val time: Long) {
    fun toPacket(): NetworkPacket = NetworkPacket(
        PacketType.LOCATION,
        NetworkPacket.body("latitude" to latitude, "longitude" to longitude, "accuracy" to accuracy, "time" to time),
    )

    companion object {
        fun request(): NetworkPacket = NetworkPacket(PacketType.LOCATION_REQUEST)

        fun fromPacket(packet: NetworkPacket): PhoneLocation? {
            if (packet.type != PacketType.LOCATION) return null

            val latitude = packet.double("latitude")?.takeIf { it in -90.0..90.0 } ?: return null
            val longitude = packet.double("longitude")?.takeIf { it in -180.0..180.0 } ?: return null

            return PhoneLocation(latitude, longitude, packet.double("accuracy") ?: 0.0, packet.long("time") ?: 0)
        }
    }
}
