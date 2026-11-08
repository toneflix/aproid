package com.toneflix.aproid

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.toneflix.aproid.protocol.Share
import java.io.FileNotFoundException
import java.io.FilterInputStream
import java.io.InputStream
import java.net.ProtocolException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** Sends files, links and text from this phone to a paired Mac. */
object ShareSender {
    data class Item(val uri: Uri, val name: String, val size: Long)

    /** One file at a time, so progress reads naturally and few ports are open. */
    private val queue = Executors.newSingleThreadExecutor()

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
     * Sends [items] one after another. [onProgress] gets the bytes sent so far across all files,
     * and [onDone] is called once at the end with the first error, if any.
     */
    fun sendFiles(
        context: Context,
        deviceId: String,
        items: List<Item>,
        onProgress: (Long) -> Unit = {},
        onDone: (Throwable?) -> Unit = {},
    ) {
        val app = context.applicationContext
        val sent = AtomicLong()

        queue.execute {
            var failure: Throwable? = null

            for (item in items) {
                val device = DeviceStore.find(deviceId)?.takeIf { it.isPaired }
                if (device == null) {
                    failure = ProtocolException("not connected")
                    break
                }

                val started = Recent.add(RecentItem.Kind.SENDING, item.name, app.getString(R.string.share_sending, device.name))
                val finished = CountDownLatch(1)
                var error: Throwable? = null

                val offered = runCatching {
                    device.sendWithPayload(Share.file(item.name, item.size), item.size, open = {
                        val input = app.contentResolver.openInputStream(item.uri) ?: throw FileNotFoundException(item.name)
                        CountingStream(input) { onProgress(sent.addAndGet(it)) }
                    }) {
                        error = it
                        finished.countDown()
                    }
                }.getOrElse { false }

                if (offered) finished.await() else error = ProtocolException("could not offer ${item.name}")

                val ok = error == null
                Recent.put(
                    started.copy(
                        kind = if (ok) RecentItem.Kind.SENT else RecentItem.Kind.FAILED,
                        detail = app.getString(if (ok) R.string.share_sent else R.string.share_send_failed, device.name),
                        time = System.currentTimeMillis(),
                    ),
                )
                if (!ok && failure == null) failure = error
            }

            onDone(failure)
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
