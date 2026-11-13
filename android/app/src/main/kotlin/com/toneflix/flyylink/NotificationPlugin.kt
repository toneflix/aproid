package com.toneflix.flyylink

import android.app.ActivityOptions
import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import com.toneflix.flyylink.protocol.Device
import com.toneflix.flyylink.protocol.NetworkPacket
import com.toneflix.flyylink.protocol.NotificationAction
import com.toneflix.flyylink.protocol.PacketType
import com.toneflix.flyylink.protocol.PhoneNotification
import com.toneflix.flyylink.protocol.Plugin
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Sends phone notifications to paired Macs and carries out their replies, button presses and dismissals. */
object NotificationPlugin : Plugin {
    private const val TAG = "FlyyLinkNotifications"

    override val incoming = setOf(PacketType.NOTIFICATION_REQUEST, PacketType.NOTIFICATION_REPLY, PacketType.NOTIFICATION_ACTION)

    private class Replyable(val key: String, val action: Notification.Action)

    private val replies = ConcurrentHashMap<String, Replyable>()

    private class SentReply(val text: String, val at: Long)

    /** The last reply sent per notification key, to recognise the update that echoes it. */
    private val sentReplies = ConcurrentHashMap<String, SentReply>()

    private const val ECHO_WINDOW_MS = 30_000L

    private const val ICON_SIZE = 96

    /** "deviceId/hash" for each icon a device already has, so it is sent only once per connection. */
    private val sentIcons = ConcurrentHashMap.newKeySet<String>()

    fun hasAccess(context: Context): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: ""
        val me = ComponentName(context, NotificationMirrorService::class.java).flattenToString()

        return enabled.split(':').contains(me)
    }

    fun accessSettingsIntent(): Intent =
        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    fun posted(context: Context, sbn: StatusBarNotification) {
        // Messaging apps repost the notification with your own reply in it. Don't mirror that back.
        if (isOwnMessage(sbn)) return

        val note = describe(context, sbn, silent = false) ?: return
        val icon = icon(context, sbn)

        DeviceStore.pairedDevices().forEach { send(it, note, icon) }
    }

    override fun onPaired(device: Device) {
        // A new connection may be to a Mac that lost its cache, so start over.
        sentIcons.removeAll { it.startsWith("${device.id}/") }
    }

    fun removed(sbn: StatusBarNotification) {
        replies.values.removeAll { it.key == sbn.key }
        sentReplies.remove(sbn.key)
        DeviceStore.sendToPaired(PhoneNotification.cancelPacket(sbn.key))
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val service = NotificationMirrorService.instance ?: return

        when (packet.type) {
            PacketType.NOTIFICATION_REQUEST -> handleRequest(service, device, packet)
            PacketType.NOTIFICATION_REPLY -> reply(service, packet)
            PacketType.NOTIFICATION_ACTION -> press(service, packet)
        }
    }

    /** Presses the notification button the Mac picked, as tapping it on the phone would. */
    private fun press(service: NotificationMirrorService, packet: NetworkPacket) {
        val pressed = NotificationAction.fromPacket(packet) ?: return
        val sbn = service.activeNotifications.orEmpty().firstOrNull { it.key == pressed.id } ?: return
        val action = buttons(sbn.notification).firstOrNull { it.title?.toString() == pressed.action } ?: return

        try {
            send(service, action.actionIntent, Intent())
        } catch (e: Exception) {
            Log.w(TAG, "Pressing ${pressed.action} on ${sbn.key} failed", e)
        }
    }

    /** The buttons the Mac can press: every action except text replies, which go through [reply]. */
    private fun buttons(notification: Notification): List<Notification.Action> =
        notification.actions.orEmpty().filter { action ->
            action.actionIntent != null &&
                !action.title.isNullOrBlank() &&
                action.remoteInputs.orEmpty().none { it.allowFreeFormInput }
        }

    private fun handleRequest(service: NotificationMirrorService, device: Device, packet: NetworkPacket) {
        packet.string("cancel")?.let { service.cancelNotification(it) }

        if (packet.bool("request") == true) {
            service.activeNotifications.orEmpty().forEach { sbn ->
                val note = describe(service, sbn, silent = true) ?: return@forEach
                send(device, note, icon(service, sbn))
            }
        }
    }

    private fun reply(context: Context, packet: NetworkPacket) {
        val replyId = packet.string("requestReplyId") ?: return
        val message = packet.string("message") ?: return
        val target = replies[replyId]
        if (target == null) {
            Log.w(TAG, "Reply for unknown notification $replyId")
            return
        }

        val inputs = target.action.remoteInputs ?: return
        val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, message) } }
        val intent = Intent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        RemoteInput.addResultsToIntent(inputs, intent, results)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            RemoteInput.setResultsSource(intent, RemoteInput.SOURCE_FREE_FORM_INPUT)
        }

        try {
            sentReplies[target.key] = SentReply(message, System.currentTimeMillis())
            send(context, target.action.actionIntent, intent)
            Log.i(TAG, "Sent reply to ${target.key}")
        } catch (e: Exception) {
            Log.w(TAG, "Reply to ${target.key} failed", e)
        }
    }

    /** Some apps answer replies by opening an activity, which Android 14 blocks from the background unless allowed. */
    private fun send(context: Context, pendingIntent: PendingIntent, fillIn: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val options = ActivityOptions.makeBasic()
                .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                .toBundle()
            pendingIntent.send(context, 0, fillIn, null, null, null, options)
        } else {
            pendingIntent.send(context, 0, fillIn)
        }
    }

    /** Sends the notification with its icon, unless the device already has that icon. */
    private fun send(device: Device, note: PhoneNotification, icon: ByteArray?) {
        if (icon == null) {
            DeviceStore.send(device, note.toPacket())
            return
        }

        val hash = PhoneNotification.iconHash(icon)
        val packet = note.copy(iconHash = hash).toPacket()
        val key = "${device.id}/$hash"

        if (!sentIcons.add(key)) {
            DeviceStore.send(device, packet)
            return
        }

        DeviceStore.sendWithPayload(device, packet, icon) { error -> if (error != null) sentIcons.remove(key) }
    }

    /** The sender's photo when the notification has one, otherwise the app icon, as a small PNG. */
    private fun icon(context: Context, sbn: StatusBarNotification): ByteArray? = runCatching {
        val drawable = sbn.notification.getLargeIcon()?.loadDrawable(context)
            ?: context.packageManager.getApplicationIcon(sbn.packageName)
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
        drawable.draw(Canvas(bitmap))

        ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }.getOrNull()

    /** True when the newest message in the notification was written by the phone's owner. */
    private fun isOwnMessage(sbn: StatusBarNotification): Boolean {
        val style = NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(sbn.notification)
        val last = style?.messages?.lastOrNull()
        if (last != null) {
            val sender = last.person ?: return true
            val me = style.user
            val sameKey = sender.key != null && sender.key == me.key
            val sameName = sender.name != null && sender.name.toString() == me.name?.toString()

            return sameKey || sameName
        }

        val sent = sentReplies[sbn.key] ?: return false
        val text = sbn.notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()

        return System.currentTimeMillis() - sent.at < ECHO_WINDOW_MS && text.contains(sent.text)
    }

    /** Null for notifications we don't mirror: our own, ongoing ones, group summaries and empty ones. */
    private fun describe(context: Context, sbn: StatusBarNotification, silent: Boolean): PhoneNotification? {
        val notification = sbn.notification
        if (sbn.packageName == context.packageName) return null
        if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return null
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return null

        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))
            ?.toString().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return null

        return PhoneNotification(
            id = sbn.key,
            appName = appName(context, sbn.packageName),
            title = title,
            text = text,
            time = sbn.postTime,
            isClearable = sbn.isClearable,
            replyId = replyIdFor(sbn),
            silent = silent,
            actions = buttons(notification).map { it.title.toString() }.distinct(),
        )
    }

    private fun replyIdFor(sbn: StatusBarNotification): String? {
        val notification = sbn.notification
        // Messaging apps put the reply action either on the notification or only in its wearable extras.
        val candidates = notification.actions.orEmpty().toList() + Notification.WearableExtender(notification).actions
        val action = candidates.firstOrNull { candidate ->
            candidate.remoteInputs?.any { it.allowFreeFormInput } == true
        } ?: return null

        val existing = replies.entries.firstOrNull { it.value.key == sbn.key }?.key
        val id = existing ?: UUID.randomUUID().toString()
        replies[id] = Replyable(sbn.key, action)

        return id
    }

    private fun appName(context: Context, packageName: String): String {
        val pm = context.packageManager

        return try {
            pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            packageName
        }
    }
}
