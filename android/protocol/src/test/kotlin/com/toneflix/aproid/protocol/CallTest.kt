package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CallTest {
    private fun wire(packet: NetworkPacket) = NetworkPacket.parse(packet.serialize())

    @Test fun eventsRoundTrip() {
        assertEquals(
            Call.State(CallEvent.RINGING, "+2348012345678", "Ada", "aGVsbG8=", ended = false),
            Call.state(wire(Call.event(CallEvent.RINGING, "+2348012345678", "Ada", "aGVsbG8="))),
        )
        assertEquals(Call.State(CallEvent.RINGING, "555", null, null, ended = true), Call.state(wire(Call.ended("555"))))
    }

    @Test fun readsKdeConnectMissedCall() {
        val packet = NetworkPacket.parse("""{"id":1,"type":"kdeconnect.telephony","body":{"event":"missedCall","phoneNumber":"555","contactName":"Bo"}}""")

        assertEquals(Call.State(CallEvent.MISSED, "555", "Bo", null, ended = false), Call.state(packet))
    }

    @Test fun requestsRoundTrip() {
        assertEquals(Call.Request(Call.Action.ANSWER), Call.request(wire(Call.answer())))
        assertEquals(Call.Request(Call.Action.DECLINE), Call.request(wire(Call.decline())))
        assertEquals(Call.Request(Call.Action.HANG_UP), Call.request(wire(Call.hangUp())))
        assertEquals(Call.Request(Call.Action.DIAL, "+234801"), Call.request(wire(Call.dial("+234801"))))
    }

    @Test fun dialNeedsANumber() {
        assertNull(Call.request(wire(Call.dial(" "))))
        assertNull(Call.state(wire(Call.answer())))
    }
}
