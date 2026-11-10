package com.toneflix.aproid

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PacketType
import com.toneflix.aproid.protocol.Plugin
import com.toneflix.aproid.protocol.Screen
import com.toneflix.aproid.protocol.ScreenInput

/**
 * Mirrors the screen to the Mac when it asks, and plays back its taps, swipes and typing.
 * Android needs the user to allow each recording, so a request from the Mac shows a notification to tap.
 */
object ScreenPlugin : Plugin {
    const val CHANNEL_ID = "screen"
    private const val ASK_NOTIFICATION_ID = 4

    override val incoming = setOf(PacketType.SCREEN_REQUEST, PacketType.SCREEN_INPUT)

    /** Who to stream to once the user allows the recording. */
    data class Pending(val deviceId: String, val maxSize: Int, val bitrate: Int, val audio: Boolean)

    @Volatile var pending: Pending? = null
        private set

    private var context: Context? = null

    fun start(context: Context) {
        this.context = context.applicationContext
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val context = context ?: return

        Screen.request(packet)?.let { request ->
            when (request.action) {
                Screen.Action.START -> ask(context, device, request)
                Screen.Action.STOP -> ScreenService.stop(context)
            }
        }

        ScreenInput.fromPacket(packet)?.let { input ->
            if (ScreenService.isRunning) ScreenControlService.perform(input)
        }
    }

    /** Starts mirroring from the phone itself, to the Mac the user picked. */
    fun mirror(context: Context, deviceId: String) {
        // Computers that can't play sound skip its frames, so always offer it.
        pending = Pending(deviceId, Screen.MAX_SIZE, Screen.BITRATE, audio = true)
        context.startActivity(captureIntent(context))
    }

    private fun ask(context: Context, device: Device, request: Screen.Request) {
        if (ScreenService.isRunning) return

        pending = Pending(device.id, request.maxSize, request.bitrate, request.audio)

        // Android only lets the app open the permission screen from the background when tapped.
        val tap = PendingIntent.getActivity(context, 4, captureIntent(context), PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.lucide_cast)
            .setContentTitle(context.getString(R.string.screen_ask_title, device.name))
            .setContentText(context.getString(R.string.screen_ask_text))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_CALL)
            .build()

        context.getSystemService(NotificationManager::class.java).notify(ASK_NOTIFICATION_ID, notification)
        runCatching { context.startActivity(captureIntent(context)) }
    }

    fun clearAsk(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(ASK_NOTIFICATION_ID)
    }

    private fun captureIntent(context: Context) =
        Intent(context, ScreenCaptureActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
