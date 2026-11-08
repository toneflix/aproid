package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DevicePluginsTest {
    @Test fun batteryRoundTrips() {
        val status = BatteryStatus(charge = 42, isCharging = true)

        assertEquals(status, BatteryStatus.fromPacket(NetworkPacket.parse(status.toPacket().serialize())))
    }

    @Test fun batteryIsLowOnlyWhenNotCharging() {
        assertTrue(BatteryStatus.of(charge = 15, isCharging = false).isLow)
        assertFalse(BatteryStatus.of(charge = 15, isCharging = true).isLow)
        assertFalse(BatteryStatus.of(charge = 16, isCharging = false).isLow)
    }

    @Test fun readsKdeConnectBatteryPacket() {
        val wire = """{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":9,"isCharging":false,"thresholdEvent":1}}"""

        assertEquals(BatteryStatus(9, isCharging = false, isLow = true), BatteryStatus.fromPacket(NetworkPacket.parse(wire)))
    }

    @Test fun clipboardContentComesFromBothPacketTypes() {
        assertEquals("hello", Clipboard.content(Clipboard.packet("hello")))
        assertEquals("hello", Clipboard.content(Clipboard.connectPacket("hello", 1_700_000_000_000)))
        assertNull(Clipboard.content(Clipboard.packet("")))
        assertNull(Clipboard.content(FindMyPhone.request()))
    }
}
