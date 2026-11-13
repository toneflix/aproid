package com.toneflix.flyylink

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
import com.toneflix.flyylink.protocol.Device
import com.toneflix.flyylink.protocol.NetworkPacket
import com.toneflix.flyylink.protocol.PacketType
import com.toneflix.flyylink.protocol.Plugin
import com.toneflix.flyylink.protocol.Share
import com.toneflix.flyylink.protocol.TransferProgress
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Receives what the Mac shares: files go to Downloads, links wait in a notification
 * (Android doesn't let a background app open the browser), and text goes on the clipboard.
 * A file that stops halfway resumes when the Mac reconnects, even after the app restarts.
 */
object SharePlugin : Plugin {
    const val CHANNEL_ID = "transfers"

    override val incoming = setOf(PacketType.SHARE_REQUEST, PacketType.SHARE_RESUME)

    private var context: Context? = null
    private var partials: PartialDownloads? = null

    /** The Recent entry of each unfinished file, so a resume updates the same line. */
    private val items = java.util.concurrent.ConcurrentHashMap<String, RecentItem>()
    private val main = Handler(Looper.getMainLooper())

    /** Several at once: each offer from the Mac expires if nobody downloads it within a minute. */
    private val downloads = Executors.newCachedThreadPool()
    private val notificationIds = AtomicInteger(1000)

    fun start(context: Context) {
        if (this.context != null) return

        val app = context.applicationContext
        val partials = PartialDownloads(app).also { this.partials = it }
        this.context = app

        partials.removeExpired()
        partials.all().forEach { (id, entry) ->
            items[id] = Recent.add(RecentItem.Kind.FAILED, entry.title, app.getString(R.string.share_paused, entry.deviceName))
        }
    }

    override fun onPaired(device: Device) {
        partials?.all()?.filterValues { it.deviceId == device.id }?.forEach { (id, entry) ->
            entry.target.length()?.let { DeviceStore.send(device, Share.resume(id, it)) }
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
        val partials = partials ?: return
        val id = file.transferId
        val saved = id?.let { partials[it] }?.takeIf { it.deviceId == device.id && it.target.length() == file.offset }
        val total = saved?.total ?: (file.offset + file.size)
        val detail = context.getString(R.string.share_receiving, Formatter.formatShortFileSize(context, total), device.name)
        val started = id?.let { items[it] }?.copy(kind = RecentItem.Kind.RECEIVING, detail = detail)?.also(Recent::put)
            ?: Recent.add(RecentItem.Kind.RECEIVING, file.safeName, detail)

        val target = saved?.target ?: if (file.offset == 0L) DownloadTarget.create(context, file.safeName) else null
        if (target == null) {
            Recent.put(started.copy(kind = RecentItem.Kind.FAILED, detail = context.getString(R.string.share_save_failed)))
            return
        }

        // Recorded before any bytes arrive, so a crash midway can still resume.
        if (id != null) {
            items[id] = started
            val expires = System.currentTimeMillis() + PartialDownloads.KEEP_MS
            partials.put(id, PartialDownloads.Entry(target, device.id, device.name, started.title, total, expires))
        }

        val progress = TransferProgress(total, file.offset)
        val result = runCatching {
            target.open(append = saved != null).use { sink ->
                device.receivePayload(packet, CountingSink(sink) { bytes -> progress.advance(bytes)?.let { Recent.put(started.copy(progress = it)) } })
            }
            target.publish()
        }

        if (result.isFailure) {
            if (id != null && (target.length() ?: 0) > 0) {
                // Keep what arrived; the rest comes when the Mac reconnects.
                Recent.put(started.copy(kind = RecentItem.Kind.FAILED, detail = context.getString(R.string.share_paused, device.name), progress = null))
            } else {
                id?.let(::forget)
                target.discard()
                Recent.put(started.copy(kind = RecentItem.Kind.FAILED, detail = context.getString(R.string.share_stopped, device.name), progress = null))
            }
            return
        }

        id?.let(::forget)
        val done = started.copy(
            kind = RecentItem.Kind.RECEIVED,
            detail = context.getString(R.string.share_received, device.name),
            time = System.currentTimeMillis(),
            uri = target.viewUri(),
            mimeType = target.mimeType,
            progress = null,
        )
        Recent.put(done)
        notify(context, file.safeName, context.getString(R.string.share_received_note, device.name), done.openIntent(context))
    }

    private fun forget(id: String) {
        items.remove(id)
        partials?.remove(id)
    }

    /** Reports the bytes written. */
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

        notify(context, uri.host ?: url, context.getString(R.string.share_link_tap, device.name), item.openIntent(context))
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
            .setSmallIcon(R.drawable.lucide_download)
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

/** Opens a received file or link, or null when there is nothing to open. Files go through [OpenFileActivity]. */
fun RecentItem.openIntent(context: Context): Intent? {
    val uri = uri ?: return null
    if (kind == RecentItem.Kind.LINK) return Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    return OpenFileActivity.intent(context, uri, mimeType)
}
