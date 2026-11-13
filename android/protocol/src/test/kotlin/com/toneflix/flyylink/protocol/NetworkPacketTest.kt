package com.toneflix.flyylink.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkPacketTest {
    @Test fun serializeEndsWithNewlineAndRoundTrips() {
        val p = NetworkPacket(PacketType.PING, NetworkPacket.body("message" to "hi"), id = 42)
        val wire = p.serialize()
        assertTrue(wire.endsWith("\n"))
        assertEquals(1, wire.count { it == '\n' })
        val back = NetworkPacket.parse(wire)
        assertEquals(p, back)
        assertEquals("hi", back.string("message"))
    }

    @Test fun parsesStringIdFromOlderClients() {
        val p = NetworkPacket.parse("""{"id":"123","type":"kdeconnect.ping","body":{}}""")
        assertEquals(123L, p.id)
    }

    @Test fun payloadFieldsRoundTrip() {
        val p = NetworkPacket(
            PacketType.SHARE_REQUEST,
            NetworkPacket.body("filename" to "a.jpg"),
            id = 1,
            payloadSize = 2048,
            payloadTransferInfo = NetworkPacket.body("port" to 1739),
        )
        val back = NetworkPacket.parse(p.serialize())
        assertEquals(2048L, back.payloadSize)
        assertEquals("1739", back.payloadTransferInfo?.get("port").toString())
    }

    @Test(expected = ProtocolException::class) fun rejectsMissingType() {
        NetworkPacket.parse("""{"id":1,"body":{}}""")
    }

    @Test(expected = ProtocolException::class) fun rejectsGarbage() {
        NetworkPacket.parse("not json")
    }

    @Test fun nullBodyValuesAreLeftOut() {
        val p = NetworkPacket("x", NetworkPacket.body("a" to null, "b" to 1))
        assertNull(p.body["a"])
        assertEquals(1, p.int("b"))
    }
}
