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
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
