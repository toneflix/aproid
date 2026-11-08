package com.toneflix.aproid

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager

class AproidApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            LinkService.CHANNEL_ID,
            getString(R.string.channel_link),
            NotificationManager.IMPORTANCE_MIN,
        )
        // We play the ringtone ourselves, at full volume, so the channel stays silent.
        val find = NotificationChannel(
            FindMyPhonePlugin.CHANNEL_ID,
            getString(R.string.channel_find),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { setSound(null, null) }

        val transfers = NotificationChannel(
            SharePlugin.CHANNEL_ID,
            getString(R.string.channel_transfers),
            NotificationManager.IMPORTANCE_DEFAULT,
        )

        getSystemService(NotificationManager::class.java).createNotificationChannels(listOf(channel, find, transfers))
    }
}
