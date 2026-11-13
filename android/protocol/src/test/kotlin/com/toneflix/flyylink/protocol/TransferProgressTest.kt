package com.toneflix.flyylink.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class TransferProgressTest {
    private var now = 0L
    private val second = 1_000_000_000L

    @Test fun reportsAboutTenTimesASecond() {
        val progress = TransferProgress(1000, clock = { now })

        assertNull(progress.advance(10))

        now += second / 10
        assertNotNull(progress.advance(10))
        assertNull(progress.advance(10))
    }

    @Test fun alwaysReportsTheLastBytes() {
        val progress = TransferProgress(100, clock = { now })

        assertEquals(1.0, progress.advance(100)!!.fraction, 0.0)
    }

    @Test fun holdsSpeedBackForTheFirstSecond() {
        val progress = TransferProgress(1000, clock = { now })

        now += second / 2
        val early = progress.advance(100)!!
        assertNull(early.bytesPerSecond)
        assertNull(early.secondsLeft)
    }

    @Test fun measuresSpeedAndTimeLeft() {
        val progress = TransferProgress(1000, clock = { now })

        now += 2 * second
        val reading = progress.advance(200)!!

        assertEquals(TransferProgress.Snapshot(200, 1000, 100, 8), reading)
        assertEquals(0.2, reading.fraction, 0.0001)
    }

    @Test fun resumedTransferCountsOnlyNewBytesForSpeed() {
        val progress = TransferProgress(1000, alreadyDone = 600, clock = { now })

        now += 2 * second
        val reading = progress.advance(100)!!

        assertEquals(TransferProgress.Snapshot(700, 1000, 50, 6), reading)
    }
}
