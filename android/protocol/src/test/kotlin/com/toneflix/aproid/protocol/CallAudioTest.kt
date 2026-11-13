package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CallAudioTest {
    private fun wire(packet: NetworkPacket) = NetworkPacket.parse(packet.serialize())

    @Test fun requestsRoundTrip() {
        val pair = CallAudio.Request(CallAudio.Action.PAIR, "A4:83:E7:01:02:0F", "Obi's MacBook")

        assertEquals(pair, CallAudio.request(wire(CallAudio.request(pair))))
        assertEquals(
            CallAudio.Request(CallAudio.Action.STATUS, "A4:83:E7:01:02:0F"),
            CallAudio.request(wire(CallAudio.request(CallAudio.Request(CallAudio.Action.STATUS, "a4-83-e7-01-02-0f")))),
        )
    }

    @Test fun statusRoundTrips() {
        val status = CallAudio.Status(bluetoothOn = true, allowed = true, paired = true, connected = false, name = "TECNO SPARK")

        assertEquals(status, CallAudio.status(wire(CallAudio.status(status))))
    }

    /** The same packet the Swift test reads. */
    @Test fun readsSharedStatus() {
        val packet = NetworkPacket.parse("""{"id":1,"type":"flyylink.callaudio","body":{"bluetoothOn":true,"allowed":false,"paired":false,"connected":false}}""")

        assertEquals(CallAudio.Status(bluetoothOn = true, allowed = false, paired = false, connected = false), CallAudio.status(packet))
    }

    @Test fun normalizesAddresses() {
        assertEquals("A4:83:E7:01:02:0F", CallAudio.normalizeAddress("a4-83-e7-01-02-0f"))
        assertEquals("A4:83:E7:01:02:0F", CallAudio.normalizeAddress("a483e701020f"))
        assertNull(CallAudio.normalizeAddress("a4-83-e7-01-02"))
        assertNull(CallAudio.normalizeAddress("zz-83-e7-01-02-0f"))
    }

    @Test fun requestNeedsAnAddress() {
        val packet = NetworkPacket.parse("""{"id":1,"type":"flyylink.callaudio.request","body":{"action":"pair","address":"nope"}}""")

        assertNull(CallAudio.request(packet))
    }

    @Test fun muteRoundTrips() {
        assertEquals(Call.Request(Call.Action.MUTE), Call.request(wire(Call.mute(true))))
        assertEquals(Call.Request(Call.Action.UNMUTE), Call.request(wire(Call.mute(false))))
    }
}
