package com.toneflix.aproid

import android.content.Context
import android.text.format.Formatter
import com.toneflix.aproid.protocol.TransferProgress

/** Words for a moving file, such as "120 MB of 1.2 GB · 41 MB/s · about 28 seconds left". */
object TransferText {
    fun describe(context: Context, reading: TransferProgress.Snapshot): String {
        val sizes = context.getString(R.string.share_progress, size(context, reading.done), size(context, reading.total))

        return (listOf(sizes) + speedAndTimeLeft(context, reading)).joinToString(" · ")
    }

    fun speedAndTimeLeft(context: Context, reading: TransferProgress.Snapshot): List<String> = buildList {
        reading.bytesPerSecond?.let { add(context.getString(R.string.share_speed, size(context, it))) }
        reading.secondsLeft?.let { add(timeLeft(context, it)) }
    }

    private fun timeLeft(context: Context, seconds: Long): String {
        if (seconds < 60) {
            val left = seconds.coerceAtLeast(1).toInt()
            return context.resources.getQuantityString(R.plurals.share_seconds_left, left, left)
        }

        val minutes = ((seconds + 30) / 60).toInt()
        return context.resources.getQuantityString(R.plurals.share_minutes_left, minutes, minutes)
    }

    private fun size(context: Context, bytes: Long) = Formatter.formatShortFileSize(context, bytes)
}
