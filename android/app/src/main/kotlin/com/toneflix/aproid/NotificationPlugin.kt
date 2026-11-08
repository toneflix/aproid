package com.toneflix.aproid

import android.app.Notification
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import android.service.notification.StatusBarNotification
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PacketType
import com.toneflix.aproid.protocol.PhoneNotification
import com.toneflix.aproid.protocol.Plugin
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Sends phone notifications to paired Macs and carries out their replies and dismissals. */
object NotificationPlugin : Plugin {
    override val incoming = setOf(PacketType.NOTIFICATION_REQUEST, PacketType.NOTIFICATION_REPLY)

    private class Replyable(val key: String, val action: Notification.Action)

    private val replies = ConcurrentHashMap<String, Replyable>()

    fun hasAccess(context: Context): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: ""
        val me = ComponentName(context, NotificationMirrorService::class.java).flattenToString()

        return enabled.split(':').contains(me)
    }

    fun accessSettingsIntent(): Intent =
        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    fun posted(context: Context, sbn: StatusBarNotification) {
        val note = describe(context, sbn, silent = false) ?: return

        DeviceStore.sendToPaired(note.toPacket())
    }

    fun removed(sbn: StatusBarNotification) {
        replies.values.removeAll { it.key == sbn.key }
        DeviceStore.sendToPaired(PhoneNotification.cancelPacket(sbn.key))
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val service = NotificationMirrorService.instance ?: return

        when (packet.type) {
            PacketType.NOTIFICATION_REQUEST -> handleRequest(service, device, packet)
            PacketType.NOTIFICATION_REPLY -> reply(service, packet)
        }
    }

    private fun handleRequest(service: NotificationMirrorService, device: Device, packet: NetworkPacket) {
        packet.string("cancel")?.let { service.cancelNotification(it) }

        if (packet.bool("request") == true) {
            service.activeNotifications.orEmpty()
                .mapNotNull { describe(service, it, silent = true) }
                .forEach { DeviceStore.send(device, it.toPacket()) }
        }
    }

    private fun reply(context: Context, packet: NetworkPacket) {
        val replyId = packet.string("requestReplyId") ?: return
        val message = packet.string("message") ?: return
        val target = replies[replyId] ?: return
        val inputs = target.action.remoteInputs ?: return

        val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, message) } }
        val intent = Intent()
        RemoteInput.addResultsToIntent(inputs, intent, results)

        runCatching { target.action.actionIntent.send(context, 0, intent) }
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
        )
    }

    private fun replyIdFor(sbn: StatusBarNotification): String? {
        val action = sbn.notification.actions?.firstOrNull { action ->
            action.remoteInputs?.any { it.allowFreeFormInput } == true
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
