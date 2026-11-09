package com.toneflix.aproid

import android.app.Activity
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Bundle
import android.provider.Settings

/**
 * The phone's own hotspot, which the Mac joins to get online and reach the phone. Android doesn't let apps
 * turn it on, so when the Mac asks we put the hotspot switch one tap away.
 */
object Hotspot {
    const val CHANNEL_ID = "hotspot"
    private const val NOTIFICATION_ID = 4100

    /** Whether the hotspot is on. Android hides this, so it reads false when the phone won't say. */
    fun isOn(context: Context): Boolean = runCatching {
        val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
        WifiManager::class.java.getMethod("isWifiApEnabled").invoke(wifi) as Boolean
    }.getOrDefault(false)

    /** Asks the user to turn the hotspot on. Opens the switch right away when the app is in front. */
    fun ask(context: Context) {
        val tap = PendingIntent.getActivity(context, NOTIFICATION_ID, settingsIntent(context), PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle(context.getString(R.string.hotspot_ask_title))
            .setContentText(context.getString(R.string.hotspot_ask_text))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setTimeoutAfter(ASK_TIMEOUT_MS)
            .build()

        runCatching { context.getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification) }
        runCatching { context.startActivity(settingsIntent(context)) }
    }

    fun clearAsk(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun settingsIntent(context: Context) =
        Intent(context, HotspotSettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Where phones keep the hotspot switch, most specific first. Makers move it, so the last ones are fallbacks. */
    internal val settingsScreens: List<Intent>
        get() = listOf(
            Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.TetherSettings")),
            Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.Settings\$TetherSettingsActivity")),
            Intent(Settings.ACTION_WIRELESS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )

    private const val ASK_TIMEOUT_MS = 2 * 60 * 1000L
}

/** Opens the hotspot settings from the notification, trying each place phones keep them. */
class HotspotSettingsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Hotspot.clearAsk(this)

        Hotspot.settingsScreens.firstOrNull { runCatching { startActivity(it) }.isSuccess }
        finish()
    }
}
