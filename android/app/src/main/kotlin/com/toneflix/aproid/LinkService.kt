package com.toneflix.aproid

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.LanLink
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Keeps the phone reachable from the Mac: listens for connections and announces
 * itself on the local network every few seconds.
 */
class LinkService : Service() {
    @Volatile private var link: LanLink? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var scheduler: ScheduledExecutorService? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        if (scheduler == null) startLink()
        return START_STICKY
    }

    override fun onDestroy() {
        scheduler?.shutdownNow()
        link?.stop()
        DeviceStore.clear()
        multicastLock?.release()
        link = null
        scheduler = null
        super.onDestroy()
    }

    private fun startLink() {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("aproid").apply {
            setReferenceCounted(false)
            acquire()
        }

        val exec = Executors.newSingleThreadScheduledExecutor()
        scheduler = exec

        // Creating the certificate on first launch is slow, so keep it off the main thread.
        exec.execute {
            val certificate = DeviceStore.certificate(this)
            val trustStore = DeviceStore.trustStore(this)
            val newLink = LanLink(
                identityProvider = { DeviceStore.identity(this) },
                certificate = certificate,
                trustStore = trustStore,
                onLink = { DeviceStore.add(Device(it, certificate, trustStore)) },
            )

            runCatching { newLink.start() }
            link = newLink
        }

        exec.scheduleWithFixedDelay({
            runCatching { link?.broadcastIdentity() }
            DeviceStore.tickAll()
        }, 1, 5, TimeUnit.SECONDS)
    }

    private fun startForegroundCompat() {
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.notification_running))
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val CHANNEL_ID = "link"
        private const val NOTIFICATION_ID = 1

        fun start(context: Context) {
            context.startForegroundService(Intent(context, LinkService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LinkService::class.java))
        }
    }
}
