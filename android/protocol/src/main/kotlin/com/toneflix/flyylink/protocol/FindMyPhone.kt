package com.toneflix.flyylink.protocol

/** Asks the phone to ring until someone finds it ("kdeconnect.findmyphone.request"). */
object FindMyPhone {
    fun request(): NetworkPacket = NetworkPacket(PacketType.FIND_MY_PHONE)
}
