package com.toneflix.aproid

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PacketType
import com.toneflix.aproid.protocol.Plugin

/** Rings the phone at full volume when a paired Mac asks, until the user taps "Found it". */
object FindMyPhonePlugin : Plugin {
    const val CHANNEL_ID = "find"
    private const val NOTIFICATION_ID = 2

    override val incoming = setOf(PacketType.FIND_MY_PHONE)

    private var context: Context? = null
    private var player: MediaPlayer? = null
    private var savedVolume: Int? = null

    fun start(context: Context) {
        this.context = context.applicationContext
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val context = context ?: return

        ring(context, device.name)
    }

    @Synchronized private fun ring(context: Context, from: String) {
        if (player != null) return

        val audio = context.getSystemService(AudioManager::class.java)
        savedVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)

        val uri = RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        player = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
                setDataSource(context, uri)
                isLooping = true
                prepare()
                start()
            }
        }.getOrNull()

        context.getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(context, from))
    }

    @Synchronized fun stop(context: Context) {
        player?.runCatching { stop(); release() }
        player = null

        savedVolume?.let { context.getSystemService(AudioManager::class.java).setStreamVolume(AudioManager.STREAM_ALARM, it, 0) }
        savedVolume = null

        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun notification(context: Context, from: String): Notification {
        val stop = PendingIntent.getBroadcast(
            context, 0, Intent(context, StopRingingReceiver::class.java), PendingIntent.FLAG_IMMUTABLE,
        )

        return Notification.Builder(context, CHANNEL_ID)
            .setContentTitle(context.getString(R.string.find_title))
            .setContentText(context.getString(R.string.find_text, from))
            .setSmallIcon(R.drawable.lucide_bell_ring)
            .setContentIntent(stop)
            .setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(null, context.getString(R.string.find_stop), stop).build())
            .setCategory(Notification.CATEGORY_ALARM)
            .build()
    }

    /** Stops the ringing from the notification. */
    class StopRingingReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = stop(context)
    }
}
