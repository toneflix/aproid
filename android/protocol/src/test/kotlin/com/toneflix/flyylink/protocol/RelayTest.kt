package com.toneflix.flyylink.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RelayTest {
    private fun wire(packet: NetworkPacket) = NetworkPacket.parse(packet.serialize())

    @Test fun phonePacketsRoundTrip() {
        val call = Call.event(CallEvent.RINGING, "+2348000000000", "Ada")
        val message = Relay.message(wire(Relay.wrap(call, "phone1", "Pixel")))!!

        assertEquals("phone1", message.phoneId)
        assertEquals("Pixel", message.phoneName)
        assertEquals(PacketType.TELEPHONY, message.packet.type)
        assertEquals(call.body, message.packet.body)
    }

    @Test fun answersRoundTrip() {
        val reply = NotificationRequests.reply("r1", "On my way")
        val message = Relay.message(wire(Relay.wrap(reply, "phone1", "Pixel")))!!

        assertEquals(reply.type, message.packet.type)
        assertEquals(reply.body, message.packet.body)
    }

    @Test fun onlyRelayablePacketsAreAccepted() {
        assertNull(Relay.message(wire(Relay.wrap(NetworkPacket(PacketType.PING), "phone1", "Pixel"))))
        assertNull(Relay.message(wire(Relay.wrap(Call.event(CallEvent.MISSED, "1"), "", "Pixel"))))
        assertNull(Relay.message(NetworkPacket(PacketType.RELAY, NetworkPacket.body("phoneId" to "phone1"))))
        assertEquals("Phone", Relay.message(wire(Relay.wrap(Call.event(CallEvent.MISSED, "1"), "p", "")))?.phoneName)
    }
}
