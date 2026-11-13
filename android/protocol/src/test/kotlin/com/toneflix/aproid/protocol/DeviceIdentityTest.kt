package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceIdentityTest {
    @Test fun newIdsAreValid() {
        repeat(20) { assertTrue(DeviceIdentity.isValidDeviceId(DeviceIdentity.newDeviceId())) }
        assertFalse(DeviceIdentity.isValidDeviceId("short"))
        assertFalse(DeviceIdentity.isValidDeviceId("has-dashes-0000000000000000000000000"))
    }

    @Test fun announcementFitsInOnePacket() {
        val capabilities = (0 until 120).map { "flyylink.capability.$it" }.toSet()
        val identity = DeviceIdentity(
            DeviceIdentity.newDeviceId(), "x".repeat(32), DeviceType.PHONE,
            incomingCapabilities = capabilities, outgoingCapabilities = capabilities, tcpPort = 1716,
        )

        val data = identity.announcement().serialize()
        val heard = DeviceIdentity.fromPacket(NetworkPacket.parse(data))

        assertTrue(data.toByteArray().size < 1200)
        assertEquals(identity.deviceId, heard.deviceId)
        assertEquals(1716, heard.tcpPort)
        assertTrue(heard.incomingCapabilities.isEmpty())
    }

    @Test fun sanitizesNames() {
        assertEquals("Obis Pixel", DeviceIdentity.sanitizeName("Obi's Pixel!"))
        assertEquals("Android", DeviceIdentity.sanitizeName("..."))
        assertEquals(32, DeviceIdentity.sanitizeName("x".repeat(50)).length)
    }

    @Test fun roundTripsThroughPacket() {
        val id = DeviceIdentity(DeviceIdentity.newDeviceId(), "Pixel 9", DeviceType.PHONE, tcpPort = 1716)
        val back = DeviceIdentity.fromPacket(NetworkPacket.parse(id.toPacket().serialize()))
        assertEquals(id, back)
    }

    @Test fun readsKdeConnectIdentity() {
        val wire = """{"id":1700000000000,"type":"kdeconnect.identity","body":{"deviceId":"_0123456789abcdef0123456789abcdef_","deviceName":"laptop","deviceType":"laptop","protocolVersion":8,"incomingCapabilities":["kdeconnect.ping"],"outgoingCapabilities":[],"tcpPort":1716}}"""
        val id = DeviceIdentity.fromPacket(NetworkPacket.parse(wire))
        assertEquals(DeviceType.LAPTOP, id.deviceType)
        assertEquals(8, id.protocolVersion)
        assertEquals(setOf("kdeconnect.ping"), id.incomingCapabilities)
    }

    @Test fun tellsComputersFromPhones() {
        assertTrue(DeviceType.LAPTOP.isComputer)
        assertTrue(DeviceType.DESKTOP.isComputer)
        assertFalse(DeviceType.PHONE.isComputer)
        assertTrue(DeviceType.TABLET.isPhone)
        assertFalse(DeviceType.TV.isPhone)
    }

    @Test fun phonesNeverPairWithPhones() {
        assertFalse(DeviceType.PHONE.pairsWith(DeviceType.TABLET))
        assertTrue(DeviceType.PHONE.pairsWith(DeviceType.LAPTOP))
        assertTrue(DeviceType.DESKTOP.pairsWith(DeviceType.LAPTOP))
    }
}
