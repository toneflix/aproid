package com.toneflix.flyylink.protocol

import kotlin.math.ceil

/**
 * Tracks how far a file transfer has got, how fast it is moving and how long is left.
 * Safe to advance from a network thread and read from the UI. Mirrors TransferProgress.swift.
 */
class TransferProgress(
    val total: Long,
    alreadyDone: Long = 0,
    private val clock: () -> Long = System::nanoTime,
) {
    /** One reading, safe to hand to the UI. */
    data class Snapshot(val done: Long, val total: Long, val bytesPerSecond: Long?, val secondsLeft: Long?) {
        val fraction: Double get() = if (total <= 0) 1.0 else (done.toDouble() / total).coerceIn(0.0, 1.0)
    }

    private val startedAt = clock()
    private val startedWith = alreadyDone.coerceIn(0, total.coerceAtLeast(0))
    private var done = startedWith
    private var reportedAt = startedAt

    /** Adds [bytes] and returns a reading when the UI is due one, about ten times a second. */
    @Synchronized
    fun advance(bytes: Long): Snapshot? {
        done = (done + bytes).coerceAtMost(total)
        val now = clock()
        if (now - reportedAt < REPORT_EVERY_NS && done < total) return null

        reportedAt = now
        return snapshot(now)
    }

    @Synchronized
    fun snapshot(): Snapshot = snapshot(clock())

    private fun snapshot(now: Long): Snapshot {
        val seconds = (now - startedAt) / 1e9
        val moved = done - startedWith
        val speed = if (seconds >= MIN_SECONDS && moved > 0) (moved / seconds).toLong().coerceAtLeast(1) else null
        val left = speed?.let { ceil((total - done).toDouble() / it).toLong() }

        return Snapshot(done, total, speed, left)
    }

    private companion object {
        const val REPORT_EVERY_NS = 100_000_000L

        /** Speed reads wildly in the first moments, so it is held back until then. */
        const val MIN_SECONDS = 1.0
    }
}
