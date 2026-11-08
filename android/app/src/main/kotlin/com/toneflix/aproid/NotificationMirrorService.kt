package com.toneflix.aproid

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** The system hands us every notification here; [NotificationPlugin] decides what to mirror. */
class NotificationMirrorService : NotificationListenerService() {
    override fun onListenerConnected() {
        instance = this
        MediaPlugin.start(this)
    }

    override fun onListenerDisconnected() {
        instance = null
        MediaPlugin.stop()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        NotificationPlugin.posted(this, sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        NotificationPlugin.removed(sbn)
    }

    companion object {
        @Volatile var instance: NotificationMirrorService? = null
            private set
    }
}
