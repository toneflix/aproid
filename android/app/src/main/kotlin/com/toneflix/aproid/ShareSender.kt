package com.toneflix.aproid

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.toneflix.aproid.protocol.Share
import com.toneflix.aproid.protocol.TransferProgress
import java.io.FileNotFoundException
import java.io.FilterInputStream
import java.io.InputStream
import java.net.ProtocolException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

/** Sends files, links and text from this phone to a paired Mac. */
object ShareSender {
    data class Item(val uri: Uri, val name: String, val size: Long)

    /** One file at a time, so progress reads naturally and few ports are open. */
    private val queue = Executors.newSingleThreadExecutor()

    /** A file we offered, kept for a while so the Mac can ask for the rest after a drop. */
    private class Offered(val item: Item, val deviceId: String, val recent: RecentItem, val expires: Long)

    private val offered = java.util.concurrent.ConcurrentHashMap<String, Offered>()
    private const val KEEP_OFFERS_MS = 24 * 60 * 60 * 1000L

    /** Looks up each file's name and size. */
    fun describe(context: Context, uris: List<Uri>): List<Item> = uris.mapNotNull { uri ->
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null

                val name = cursor.getString(0) ?: uri.lastPathSegment ?: "file"
                val size = if (cursor.isNull(1)) -1L else cursor.getLong(1)
                Item(uri, name, size)
            }
            ?.takeIf { it.size >= 0 }
    }

    /**
     * Sends [items] one after another. [onProgress] gets readings across all files, about ten
     * times a second, and [onDone] is called once at the end with the first error, if any.
     */
    fun sendFiles(
        context: Context,
        deviceId: String,
        items: List<Item>,
        onProgress: (TransferProgress.Snapshot) -> Unit = {},
        onDone: (Throwable?) -> Unit = {},
    ) {
        val app = context.applicationContext
        val progress = TransferProgress(items.sumOf { it.size })

        queue.execute {
            var failure: Throwable? = null

            for (item in items) {
                val device = DeviceStore.find(deviceId)?.takeIf { it.isPaired }
                if (device == null) {
                    failure = ProtocolException("not connected")
                    break
                }

                val started = Recent.add(RecentItem.Kind.SENDING, item.name, app.getString(R.string.share_sending, device.name))
                val id = java.util.UUID.randomUUID().toString()
                offered.values.removeAll { it.expires < System.currentTimeMillis() }
                offered[id] = Offered(item, device.id, started, System.currentTimeMillis() + KEEP_OFFERS_MS)

                val error = offer(app, device, item, id, 0, started) { bytes -> progress.advance(bytes)?.let(onProgress) }
                if (error != null && failure == null) failure = error
            }

            onDone(failure)
        }
    }

    /** Sends the rest of a file the Mac stopped receiving at [offset]. */
    fun resume(context: Context, device: com.toneflix.aproid.protocol.Device, id: String, offset: Long) {
        val file = offered[id]?.takeIf { it.deviceId == device.id } ?: return
        val app = context.applicationContext

        queue.execute {
            val resuming = file.recent.copy(kind = RecentItem.Kind.SENDING, detail = app.getString(R.string.share_resuming, device.name))
            Recent.put(resuming)
            offer(app, device, file.item, id, offset, resuming) {}
        }
    }

    /** Offers one file from [offset] and waits until the Mac has it. Returns the error, if any. */
    private fun offer(
        app: Context,
        device: com.toneflix.aproid.protocol.Device,
        item: Item,
        id: String,
        offset: Long,
        recent: RecentItem,
        onRead: (Long) -> Unit,
    ): Throwable? {
        val start = offset.coerceIn(0, item.size)
        val finished = CountDownLatch(1)
        var error: Throwable? = null
        val progress = TransferProgress(item.size, start)
        val onBytes: (Long) -> Unit = { bytes ->
            onRead(bytes)
            progress.advance(bytes)?.let { Recent.put(recent.copy(progress = it)) }
        }

        val packet = Share.file(item.name, item.size, transferId = id, offset = start)
        val wasOffered = runCatching {
            device.sendWithPayload(packet, item.size - start, open = {
                val input = app.contentResolver.openInputStream(item.uri) ?: throw FileNotFoundException(item.name)
                input.skipFully(start)
                CountingStream(input, onBytes)
            }) {
                error = it
                finished.countDown()
            }
        }.getOrElse { false }

        if (wasOffered) finished.await() else error = ProtocolException("could not offer ${item.name}")

        val ok = error == null
        if (ok) offered.remove(id)
        Recent.put(
            recent.copy(
                kind = if (ok) RecentItem.Kind.SENT else RecentItem.Kind.FAILED,
                detail = app.getString(if (ok) R.string.share_sent else R.string.share_paused, device.name),
                time = System.currentTimeMillis(),
                progress = null,
            ),
        )

        return error
    }

    private fun InputStream.skipFully(count: Long) {
        var left = count
        while (left > 0) {
            val skipped = skip(left)
            if (skipped <= 0) {
                if (read() < 0) throw java.io.EOFException("file is shorter than expected")
                left -= 1
            } else {
                left -= skipped
            }
        }
    }

    /** Sends a link or some text. Returns false when the Mac is not connected. */
    fun sendText(context: Context, deviceId: String, text: String): Boolean {
        val device = DeviceStore.find(deviceId)?.takeIf { it.isPaired } ?: return false
        val trimmed = text.trim()
        val isLink = Uri.parse(trimmed).scheme?.lowercase() in setOf("http", "https") && trimmed.none { it.isWhitespace() }

        DeviceStore.send(device, if (isLink) Share.link(trimmed) else Share.text(trimmed))

        val kind = if (isLink) RecentItem.Kind.LINK else RecentItem.Kind.TEXT
        val title = if (isLink) Uri.parse(trimmed).host ?: trimmed else "“${trimmed.lineSequence().first().take(80)}”"
        Recent.add(kind, title, context.getString(R.string.share_sent, device.name))

        return true
    }

    /** Reports how many bytes have been read. */
    private class CountingStream(input: InputStream, private val onRead: (Long) -> Unit) : FilterInputStream(input) {
        override fun read(): Int = super.read().also { if (it >= 0) onRead(1) }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
            super.read(buffer, offset, length).also { if (it > 0) onRead(it.toLong()) }
    }
}
