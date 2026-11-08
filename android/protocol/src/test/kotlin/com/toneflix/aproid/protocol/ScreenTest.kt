package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenTest {
    private fun wire(packet: NetworkPacket) = NetworkPacket.parse(packet.serialize())

    @Test fun requestsRoundTripWithinLimits() {
        assertEquals(Screen.Request(Screen.Action.START, 1280, 4_000_000), Screen.request(wire(Screen.start(1280, 4_000_000))))
        assertEquals(Screen.Request(Screen.Action.START, 4096, 50_000_000), Screen.request(wire(Screen.start(99_999, 900_000_000))))
        assertEquals(Screen.Action.STOP, Screen.request(wire(Screen.stop()))?.action)
        assertEquals(Screen.Info(1080, 2400, true), Screen.info(wire(Screen.started(1080, 2400))))
        assertEquals(false, Screen.info(wire(Screen.stopped()))?.running)
    }

    @Test fun inputRoundTripsAndRejectsNonsense() {
        val inputs = listOf(
            ScreenInput.Tap(0.5, 0.25),
            ScreenInput.LongPress(0.0, 1.0),
            ScreenInput.Swipe(0.5, 0.8, 0.5, 0.2, 300),
            ScreenInput.Text("hello"),
            ScreenInput.Key(ScreenInput.BACK),
        )

        for (input in inputs) assertEquals(input, ScreenInput.fromPacket(wire(input.toPacket())))
        assertNull(ScreenInput.fromPacket(wire(ScreenInput.Tap(1.5, 0.2).toPacket())))
        assertNull(ScreenInput.fromPacket(wire(ScreenInput.Key("reboot").toPacket())))
    }

    @Test fun readerRebuildsFramesSplitAnywhere() {
        val frames = listOf(
            ScreenFrame(byteArrayOf(0, 0, 0, 1, 0x67), 0, ScreenFrame.CONFIG),
            ScreenFrame(ByteArray(5000) { it.toByte() }, 33_333, ScreenFrame.KEY),
            ScreenFrame(byteArrayOf(9, 9), 50_000, 0),
        )
        val stream = frames.fold(ByteArray(0)) { all, frame -> all + frame.header() + frame.data }
        val reader = ScreenFrame.Reader()

        val out = stream.toList().chunked(7).flatMap { reader.feed(it.toByteArray()) }

        assertEquals(frames, out)
        assertTrue(out[0].isConfig && out[1].isKey)
    }
}
