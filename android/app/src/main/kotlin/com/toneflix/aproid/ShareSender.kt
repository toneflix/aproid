package com.toneflix.aproid

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.toneflix.aproid.protocol.FlyyDrop
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.Share
import com.toneflix.aproid.protocol.TransferProgress
import java.io.FileNotFoundException
import java.io.FilterInputStream
import java.io.InputStream
import java.net.ProtocolException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

/** Sends files, links and text from this phone to a paired Mac, or to any nearby device that accepted a FlyyDrop. */
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
     * With [flyyDropId] the files belong to an accepted FlyyDrop, which can't be resumed.
     */
    fun sendFiles(
        context: Context,
        deviceId: String,
        items: List<Item>,
        flyyDropId: String? = null,
        onProgress: (TransferProgress.Snapshot) -> Unit = {},
        onDone: (Throwable?) -> Unit = {},
    ) {
        val app = context.applicationContext
        val progress = TransferProgress(items.sumOf { it.size })

        queue.execute {
            var failure: Throwable? = null

            for (item in items) {
                val device = DeviceStore.find(deviceId)?.takeIf { it.isPaired || flyyDropId != null }
                if (device == null) {
                    failure = ProtocolException("not connected")
                    break
                }

                val started = Recent.add(RecentItem.Kind.SENDING, item.name, app.getString(R.string.share_sending, device.name))
                val packet = if (flyyDropId != null) {
                    FlyyDrop.file(flyyDropId, FlyyDrop.Item(item.name, item.size))
                } else {
                    val id = java.util.UUID.randomUUID().toString()
                    offered.values.removeAll { it.expires < System.currentTimeMillis() }
                    offered[id] = Offered(item, device.id, started, System.currentTimeMillis() + KEEP_OFFERS_MS)
                    Share.file(item.name, item.size, transferId = id)
                }

                val error = offer(app, device, item, packet, started) { bytes -> progress.advance(bytes)?.let(onProgress) }
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
            offer(app, device, file.item, Share.file(file.item.name, file.item.size, transferId = id, offset = offset), resuming) {}
        }
    }

    /** Offers one file with [packet], from the offset it names, and waits until the peer has it. Returns the error, if any. */
    private fun offer(
        app: Context,
        device: com.toneflix.aproid.protocol.Device,
        item: Item,
        packet: NetworkPacket,
        recent: RecentItem,
        onRead: (Long) -> Unit,
    ): Throwable? {
        val id = packet.string("aproid.transferId")
        val start = (packet.long("aproid.offset") ?: 0).coerceIn(0, item.size)
        val finished = CountDownLatch(1)
        var error: Throwable? = null
        val progress = TransferProgress(item.size, start)
        val onBytes: (Long) -> Unit = { bytes ->
            onRead(bytes)
            progress.advance(bytes)?.let { Recent.put(recent.copy(progress = it)) }
        }

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
        if (ok && id != null) offered.remove(id)
        val failed = if (id != null) R.string.share_paused else R.string.share_send_failed
        Recent.put(
            recent.copy(
                kind = if (ok) RecentItem.Kind.SENT else RecentItem.Kind.FAILED,
                detail = app.getString(if (ok) R.string.share_sent else failed, device.name),
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

    /** Sends a link or some text, as part of an accepted FlyyDrop when [flyyDropId] is set. Returns false when the device is not connected. */
    fun sendText(context: Context, deviceId: String, text: String, flyyDropId: String? = null): Boolean {
        val device = DeviceStore.find(deviceId)?.takeIf { it.isPaired || flyyDropId != null } ?: return false
        val trimmed = if (flyyDropId != null) text else text.trim()
        val isLink = Uri.parse(trimmed).scheme?.lowercase() in setOf("http", "https") && trimmed.none { it.isWhitespace() }
        val packet = when {
            flyyDropId != null -> FlyyDrop.text(flyyDropId, trimmed)
            isLink -> Share.link(trimmed)
            else -> Share.text(trimmed)
        }

        DeviceStore.send(device, packet)

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
