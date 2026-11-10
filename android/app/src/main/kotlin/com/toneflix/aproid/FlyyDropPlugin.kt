package com.toneflix.aproid

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.text.format.Formatter
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.DeviceType
import com.toneflix.aproid.protocol.FlyyDrop
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PacketType
import com.toneflix.aproid.protocol.Plugin
import com.toneflix.aproid.protocol.TransferProgress
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.concurrent.ConcurrentHashMap

/** A FlyyDrop someone nearby wants to send, waiting for the user to answer. */
data class FlyyDropAsk(val offer: FlyyDrop.Offer, val deviceName: String, val deviceType: DeviceType, val isPaired: Boolean)

/** How a FlyyDrop to one device is going. */
data class FlyyDropSend(
    val id: String,
    val stage: Stage,
    val progress: TransferProgress.Snapshot? = null,
    val reason: FlyyDrop.Reason? = null,
) {
    enum class Stage { WAITING, SENDING, SENT, DECLINED, NO_ANSWER, FAILED }

    val isFinished: Boolean get() = stage != Stage.WAITING && stage != Stage.SENDING
}

/**
 * FlyyDrop on the phone: asks nearby devices, paired or not, to take files or a link, and asks the user before
 * taking theirs. [drop] is the one authority on what an unpaired device may send or receive; accepted files then
 * move through [ShareSender] and [SharePlugin] like any other share.
 */
object FlyyDropPlugin : Plugin {
    const val CHANNEL_ID = "flyydrop"

    private const val PREFS = "aproid"
    private const val KEY_RECEIVING = "flyydrop_receiving"
    private const val KEY_UNTIL = "flyydrop_until"
    private const val ACTION_ACCEPT = "com.toneflix.aproid.FLYYDROP_ACCEPT"
    private const val ACTION_DECLINE = "com.toneflix.aproid.FLYYDROP_DECLINE"
    private const val EXTRA_ID = "id"

    val drop = FlyyDrop()

    override val incoming = setOf(PacketType.FLYYDROP_REQUEST, PacketType.FLYYDROP_RESPONSE, PacketType.FLYYDROP_CANCEL)

    private var context: Context? = null

    private val _asks = MutableStateFlow<List<FlyyDropAsk>>(emptyList())

    /** Requests waiting for the user, oldest first. */
    val asks: StateFlow<List<FlyyDropAsk>> = _asks.asStateFlow()

    private val _sends = MutableStateFlow<Map<String, FlyyDropSend>>(emptyMap())

    /** Our FlyyDrops, by the id of the device they go to. */
    val sends: StateFlow<Map<String, FlyyDropSend>> = _sends.asStateFlow()

    private val _receiving = MutableStateFlow(FlyyDrop.Receiving.OFF)

    /** Who may FlyyDrop to this phone without being paired. */
    val receiving: StateFlow<FlyyDrop.Receiving> = _receiving.asStateFlow()

    private val _receivingUntil = MutableStateFlow<Long?>(null)

    /** When "Everyone for 10 minutes" ends, in milliseconds. */
    val receivingUntil: StateFlow<Long?> = _receivingUntil.asStateFlow()

    /** What we asked to send, kept until the other device answers. */
    private class Pending(val items: List<ShareSender.Item>, val text: String?)

    private val pending = ConcurrentHashMap<String, Pending>()

    fun start(context: Context) {
        if (this.context != null) return

        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val mode = prefs.getString(KEY_RECEIVING, null)?.let { name -> FlyyDrop.Receiving.entries.firstOrNull { it.name == name } }

        this.context = app
        drop.restore(mode ?: FlyyDrop.Receiving.OFF, prefs.getLong(KEY_UNTIL, 0))
        publishReceiving()
    }

    fun setReceiving(context: Context, mode: FlyyDrop.Receiving) {
        drop.receiving = mode
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_RECEIVING, mode.name)
            .putLong(KEY_UNTIL, drop.receivingUntil ?: 0)
            .apply()
        publishReceiving()
    }

    // Sending

    /** Asks [deviceId] to take [items] and/or [text]. Progress shows in [sends]. */
    fun send(deviceId: String, items: List<ShareSender.Item>, text: String? = null) {
        val device = DeviceStore.find(deviceId) ?: return
        val packet = drop.request(deviceId, items.map { FlyyDrop.Item(it.name, it.size) }, text)
        val id = packet.string("id") ?: return

        pending[id] = Pending(items, text)
        _sends.update { it + (deviceId to FlyyDropSend(id, FlyyDropSend.Stage.WAITING)) }
        DeviceStore.send(device, packet)
    }

    /** Stops waiting for [deviceId] to answer. */
    fun cancelSend(deviceId: String) {
        val send = _sends.value[deviceId]?.takeIf { it.stage == FlyyDropSend.Stage.WAITING } ?: return

        pending.remove(send.id)
        drop.cancel(send.id)?.let { packet -> DeviceStore.find(deviceId)?.let { DeviceStore.send(it, packet) } }
        _sends.update { it - deviceId }
    }

    /** Forgets finished sends, so a new share sheet starts clean. */
    fun clearFinished() {
        _sends.update { sends -> sends.filterValues { !it.isFinished } }
    }

    private fun onResponse(device: Device, packet: NetworkPacket) {
        val answer = drop.onResponse(device.id, packet) ?: return
        val id = answer.offer.id
        val sent = pending.remove(id) ?: return

        if (!answer.accepted) {
            setSend(device.id, FlyyDropSend(id, FlyyDropSend.Stage.DECLINED, reason = answer.reason))
            return
        }

        val total = answer.offer.totalSize
        setSend(device.id, FlyyDropSend(id, FlyyDropSend.Stage.SENDING, TransferProgress.Snapshot(0, total, null, null)))

        sent.text?.let { ShareSender.sendText(context ?: return, device.id, it, flyyDropId = id) }
        if (sent.items.isEmpty()) {
            setSend(device.id, FlyyDropSend(id, FlyyDropSend.Stage.SENT))
            return
        }

        ShareSender.sendFiles(
            context ?: return,
            device.id,
            sent.items,
            flyyDropId = id,
            onProgress = { reading -> setSend(device.id, FlyyDropSend(id, FlyyDropSend.Stage.SENDING, reading)) },
            onDone = { error -> setSend(device.id, FlyyDropSend(id, if (error == null) FlyyDropSend.Stage.SENT else FlyyDropSend.Stage.FAILED)) },
        )
    }

    private fun setSend(deviceId: String, send: FlyyDropSend) {
        _sends.update { sends -> if (sends[deviceId]?.id == send.id) sends + (deviceId to send) else sends }
    }

    // Receiving

    fun accept(id: String) {
        val ask = take(id) ?: return
        val packet = drop.accept(id) ?: return

        DeviceStore.find(ask.offer.deviceId)?.let { DeviceStore.send(it, packet) }
    }

    fun decline(id: String) {
        val ask = take(id) ?: return
        val packet = drop.decline(id) ?: return

        DeviceStore.find(ask.offer.deviceId)?.let { DeviceStore.send(it, packet) }
    }

    private fun onRequest(device: Device, packet: NetworkPacket) {
        when (val incoming = drop.onRequest(device.id, packet, device.isPaired)) {
            is FlyyDrop.Incoming.Ask -> {
                val ask = FlyyDropAsk(incoming.offer, device.name, device.link.identity.deviceType, device.isPaired)
                _asks.update { it + ask }
                notifyAsk(ask)
            }
            is FlyyDrop.Incoming.Reply -> DeviceStore.send(device, incoming.packet)
            null -> Unit
        }
    }

    /** Removes a request from the waiting list and its notification. */
    private fun take(id: String): FlyyDropAsk? {
        val ask = _asks.value.firstOrNull { it.offer.id == id } ?: return null

        _asks.update { asks -> asks.filterNot { it.offer.id == id } }
        context?.getSystemService(NotificationManager::class.java)?.cancel(notificationId(id))

        return ask
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        when (packet.type) {
            PacketType.FLYYDROP_REQUEST -> onRequest(device, packet)
            PacketType.FLYYDROP_RESPONSE -> onResponse(device, packet)
            PacketType.FLYYDROP_CANCEL -> drop.onCancel(device.id, packet)?.let(::ended)
        }
    }

    /** Call every few seconds: drops requests nobody answered and ends "Everyone for 10 minutes". */
    fun tick() {
        drop.expire().forEach(::ended)
        if (_receiving.value != drop.receiving) publishReceiving()
    }

    private fun ended(offer: FlyyDrop.Offer) {
        take(offer.id)

        if (pending.remove(offer.id) != null) setSend(offer.deviceId, FlyyDropSend(offer.id, FlyyDropSend.Stage.NO_ANSWER))
    }

    private fun publishReceiving() {
        _receiving.value = drop.receiving
        _receivingUntil.value = drop.receivingUntil
    }

    // Notifications

    private fun notifyAsk(ask: FlyyDropAsk) {
        val context = context ?: return
        val id = ask.offer.id

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.lucide_radar)
            .setContentTitle(context.getString(R.string.flyydrop_ask_title, ask.deviceName))
            .setContentText(summary(context, ask.offer))
            .setContentIntent(MainActivity.pendingIntent(context))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setTimeoutAfter(FlyyDrop.ASK_MS)
            .setAutoCancel(true)
            .addAction(Notification.Action.Builder(null, context.getString(R.string.flyydrop_decline), action(context, ACTION_DECLINE, id)).build())
            .addAction(Notification.Action.Builder(null, context.getString(R.string.flyydrop_accept), action(context, ACTION_ACCEPT, id)).build())
            .build()

        runCatching { context.getSystemService(NotificationManager::class.java).notify(notificationId(id), notification) }
    }

    /** "3 photos · 12 MB", "report.pdf · 2 MB" or the link itself. */
    fun summary(context: Context, offer: FlyyDrop.Offer): String {
        val items = offer.items
        val images = items.isNotEmpty() && items.all { it.name.substringAfterLast('.').lowercase() in IMAGE_EXTENSIONS }
        val what = when {
            items.isEmpty() -> return offer.text?.lineSequence()?.first().orEmpty()
            items.size == 1 -> items.first().safeName
            images -> context.resources.getQuantityString(R.plurals.share_photos, items.size, items.size)
            else -> context.resources.getQuantityString(R.plurals.share_files, items.size, items.size)
        }

        return "$what · ${Formatter.formatShortFileSize(context, offer.totalSize)}"
    }

    private fun action(context: Context, action: String, id: String): PendingIntent {
        val intent = Intent(context, ActionReceiver::class.java).setAction(action).putExtra(EXTRA_ID, id)

        return PendingIntent.getBroadcast(context, notificationId(id) + action.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun notificationId(id: String): Int = 3000 + (id.hashCode() and 0xFFFF)

    private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "heif")

    /** Accept and Decline on the request notification. */
    class ActionReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val id = intent.getStringExtra(EXTRA_ID) ?: return

            when (intent.action) {
                ACTION_ACCEPT -> accept(id)
                ACTION_DECLINE -> decline(id)
            }
        }
    }
}
