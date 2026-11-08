package com.toneflix.aproid

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.LanLink
import com.toneflix.aproid.protocol.PairState
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
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
    private var wifiLock: WifiManager.WifiLock? = null
    private var scheduler: ScheduledExecutorService? = null
    private val scope = MainScope()
    private var statusText: String? = null
    private var beacon: NearbyBeacon? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        if (scheduler == null) {
            startLink()
            showConnectionState()
        } else {
            // Started again, for example after a permission was granted.
            startBeacon()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        BatteryPlugin.stop(this)
        SmsPlugin.stop(this)
        beacon?.stop()
        beacon = null
        scheduler?.shutdownNow()
        link?.stop()
        DeviceStore.clear()
        multicastLock?.release()
        wifiLock?.release()
        link = null
        scheduler = null
        super.onDestroy()
    }

    private fun startLink() {
        BatteryPlugin.start(this)
        FindMyPhonePlugin.start(this)
        ClipboardPlugin.start(this)
        SharePlugin.start(this)
        SmsPlugin.start(this)
        CallPlugin.start(this)
        LocationPlugin.start(this)
        PhotosPlugin.start(this)
        ScreenPlugin.start(this)

        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("aproid").apply {
            setReferenceCounted(false)
            acquire()
        }

        // Stops Wi-Fi power saving from dropping the connection while the screen is off.
        @Suppress("DEPRECATION")
        wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "aproid").apply {
            setReferenceCounted(false)
            acquire()
        }

        val exec = Executors.newSingleThreadScheduledExecutor()
        scheduler = exec

        // Creating the certificate on first launch is slow, so keep it off the main thread.
        exec.execute {
            val certificate = DeviceStore.certificate(this)
            val trustStore = DeviceStore.trustStore(this)
            val ownId = DeviceStore.identity(this).deviceId
            val newLink = LanLink(
                identityProvider = { DeviceStore.identity(this) },
                certificate = certificate,
                trustStore = trustStore,
                onLink = { DeviceStore.add(Device(it, certificate, trustStore), ownId) },
                isConnected = { DeviceStore.find(it)?.link?.isOpen == true },
            )

            runCatching { newLink.start() }
            link = newLink
        }

        startBeacon()

        exec.scheduleWithFixedDelay({
            runCatching { link?.broadcastIdentity() }
            DeviceStore.tickAll()
        }, 1, 5, TimeUnit.SECONDS)
    }

    /** Lets a paired Mac find the phone over Bluetooth. Safe to call again once the permission is granted. */
    private fun startBeacon() {
        val nearby = beacon ?: NearbyBeacon(this) { link?.tcpPort }.also { beacon = it }
        nearby.start()
    }

    /** Keeps the service notification saying which paired devices are connected. */
    private fun showConnectionState() {
        val manager = getSystemService(NotificationManager::class.java)

        scope.launch {
            DeviceStore.states.collect { states ->
                val names = states.filter { it.pairState == PairState.PAIRED }.map { it.name }
                val text = if (names.isEmpty()) {
                    getString(R.string.notification_running)
                } else {
                    getString(R.string.notification_connected, names.joinToString())
                }
                statusText = text
                manager.notify(NOTIFICATION_ID, buildNotification(text))
            }
        }
    }

    private fun buildNotification(text: String): Notification {
        val sendClipboard = PendingIntent.getActivity(
            this, 0, Intent(this, ClipboardActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.clipboard_send), sendClipboard).build())
            .build()
    }

    private fun startForegroundCompat() {
        val notification = buildNotification(statusText ?: getString(R.string.notification_running))
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

        /** True when Android lets the service keep its network while the phone sleeps. */
        fun isUnrestricted(context: Context): Boolean =
            context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)

        @SuppressLint("BatteryLife")
        fun unrestrictIntent(context: Context): Intent =
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))

        fun stop(context: Context) {
            context.stopService(Intent(context, LinkService::class.java))
        }
    }
}
