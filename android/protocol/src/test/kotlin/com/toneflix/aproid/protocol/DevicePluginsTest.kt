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

    @Test fun clipboardFileNeedsAPayload() {
        val announced = Clipboard.filePacket("../shot.png", "image/png")

        assertNull(Clipboard.file(announced))

        val withPayload = NetworkPacket.parse(announced.copy(payloadSize = 10).serialize())
        assertEquals(ClipboardFile("../shot.png", "image/png"), Clipboard.file(withPayload))
        assertEquals("shot.png", Clipboard.file(withPayload)?.safeName)
    }

    @Test fun clipboardContentComesFromBothPacketTypes() {
        assertEquals("hello", Clipboard.content(Clipboard.packet("hello")))
        assertEquals("hello", Clipboard.content(Clipboard.connectPacket("hello", 1_700_000_000_000)))
        assertNull(Clipboard.content(Clipboard.packet("")))
        assertNull(Clipboard.content(FindMyPhone.request()))
    }

    @Test fun sharePacketsParse() {
        val file = Share.file("a.txt", 5).copy(payloadSize = 5)

        assertEquals(Share.File("a.txt", 5), Share.fromPacket(file))
        assertEquals(Share.Link("https://example.com"), Share.fromPacket(Share.link("https://example.com")))
        assertEquals(Share.Text("hi"), Share.fromPacket(Share.text("hi")))
    }

    @Test fun sharedFileNameCannotLeaveTheFolder() {
        assertEquals("passwd", Share.File("../../etc/passwd", 1).safeName)
        assertEquals("evil.txt", Share.File("C:\\evil.txt", 1).safeName)
        assertEquals("file", Share.File("..", 1).safeName)
    }
}
