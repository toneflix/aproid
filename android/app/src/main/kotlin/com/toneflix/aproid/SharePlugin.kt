package com.toneflix.aproid

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.text.format.Formatter
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PacketType
import com.toneflix.aproid.protocol.Plugin
import com.toneflix.aproid.protocol.Share
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Receives what the Mac shares: files go to Downloads, links wait in a notification
 * (Android doesn't let a background app open the browser), and text goes on the clipboard.
 */
object SharePlugin : Plugin {
    const val CHANNEL_ID = "transfers"

    override val incoming = setOf(PacketType.SHARE_REQUEST, PacketType.SHARE_RESUME)

    /** A file that stopped arriving, waiting for the Mac to come back. */
    private class Paused(val target: DownloadTarget, val deviceId: String, val item: RecentItem, val total: Long, val received: Long)

    private val paused = java.util.concurrent.ConcurrentHashMap<String, Paused>()

    private var context: Context? = null
    private val main = Handler(Looper.getMainLooper())

    /** Several at once: each offer from the Mac expires if nobody downloads it within a minute. */
    private val downloads = Executors.newCachedThreadPool()
    private val notificationIds = AtomicInteger(1000)

    fun start(context: Context) {
        this.context = context.applicationContext
    }

    override fun onPaired(device: Device) {
        paused.filterValues { it.deviceId == device.id }.forEach { (id, file) ->
            DeviceStore.send(device, Share.resume(id, file.received))
        }
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val context = context ?: return

        Share.resumeRequest(packet)?.let { (id, offset) ->
            ShareSender.resume(context, device, id, offset)
            return
        }

        when (val share = Share.fromPacket(packet)) {
            is Share.File -> downloads.execute { receive(context, device, packet, share) }
            is Share.Link -> link(context, device, share.url)
            is Share.Text -> text(context, device, share.text)
            null -> Unit
        }
    }

    private fun receive(context: Context, device: Device, packet: NetworkPacket, file: Share.File) {
        val resumed = file.transferId?.let { paused.remove(it) }?.takeIf { it.received == file.offset }
        val total = resumed?.total ?: (file.offset + file.size)
        val size = Formatter.formatShortFileSize(context, total)
        val detail = context.getString(R.string.share_receiving, size, device.name)
        val started = resumed?.item?.copy(kind = RecentItem.Kind.RECEIVING, detail = detail)?.also(Recent::put)
            ?: Recent.add(RecentItem.Kind.RECEIVING, file.safeName, detail)

        val target = resumed?.target ?: if (file.offset == 0L) DownloadTarget.create(context, file.safeName) else null
        if (target == null) {
            Recent.put(started.copy(kind = RecentItem.Kind.FAILED, detail = context.getString(R.string.share_save_failed)))
            return
        }

        var received = file.offset
        val result = runCatching {
            target.open(append = resumed != null).use { sink ->
                device.receivePayload(packet, CountingSink(sink) { received += it })
            }
            target.publish()
        }

        if (result.isFailure) {
            val id = file.transferId
            if (id != null && received > 0) {
                // Keep what arrived; the rest comes when the Mac reconnects.
                paused[id] = Paused(target, device.id, started, total, received)
                Recent.put(started.copy(kind = RecentItem.Kind.FAILED, detail = context.getString(R.string.share_paused, device.name)))
            } else {
                target.discard()
                Recent.put(started.copy(kind = RecentItem.Kind.FAILED, detail = context.getString(R.string.share_stopped, device.name)))
            }
            return
        }

        val done = started.copy(
            kind = RecentItem.Kind.RECEIVED,
            detail = context.getString(R.string.share_received, device.name),
            time = System.currentTimeMillis(),
            uri = target.uri,
            mimeType = target.mimeType,
        )
        Recent.put(done)
        notify(context, file.safeName, context.getString(R.string.share_received_note, device.name), done.openIntent())
    }

    /** Counts the bytes written, so a stopped file knows where to resume. */
    private class CountingSink(sink: java.io.OutputStream, private val onWrite: (Long) -> Unit) : java.io.FilterOutputStream(sink) {
        override fun write(b: Int) {
            out.write(b)
            onWrite(1)
        }

        override fun write(b: ByteArray, off: Int, len: Int) {
            out.write(b, off, len)
            onWrite(len.toLong())
        }
    }

    private fun link(context: Context, device: Device, url: String) {
        val uri = Uri.parse(url)
        val item = Recent.add(RecentItem.Kind.LINK, uri.host ?: url, context.getString(R.string.share_link_from, device.name))
            .copy(uri = uri)
        Recent.put(item)

        notify(context, uri.host ?: url, context.getString(R.string.share_link_tap, device.name), item.openIntent())
    }

    private fun text(context: Context, device: Device, text: String) {
        main.post {
            context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText(device.name, text))
        }

        val preview = text.lineSequence().first().take(80)
        Recent.add(RecentItem.Kind.TEXT, "“$preview”", context.getString(R.string.share_text_copied, device.name))
    }

    private fun notify(context: Context, title: String, text: String, intent: Intent?) {
        val tap = intent?.let {
            PendingIntent.getActivity(context, notificationIds.get(), it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()

        runCatching {
            context.getSystemService(NotificationManager::class.java).notify(notificationIds.incrementAndGet(), notification)
        }
    }
}

/** Opens a received file or link, or null when there is nothing to open. */
fun RecentItem.openIntent(): Intent? {
    val uri = uri ?: return null

    return Intent(Intent.ACTION_VIEW)
        .apply { if (mimeType != null) setDataAndType(uri, mimeType) else data = uri }
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
}
