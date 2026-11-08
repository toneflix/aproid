package com.toneflix.aproid

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PacketType
import com.toneflix.aproid.protocol.PhoneLocation
import com.toneflix.aproid.protocol.Plugin
import java.util.concurrent.Executors

/** Tells the Mac where the phone is, so it can be found on a map. */
object LocationPlugin : Plugin {
    override val incoming = setOf(PacketType.LOCATION_REQUEST)

    private var context: Context? = null
    private val worker = Executors.newSingleThreadExecutor()

    val permissions = arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

    fun hasPermission(context: Context) =
        context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** Android only gives the location to a background app once the user allows it "all the time". */
    fun hasBackgroundPermission(context: Context) =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            context.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun start(context: Context) {
        this.context = context.applicationContext
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val context = context ?: return
        if (!hasPermission(context)) return

        locate(context, device)
    }

    @SuppressLint("MissingPermission")
    private fun locate(context: Context, device: Device) {
        val manager = context.getSystemService(LocationManager::class.java)
        val providers = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.GPS_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
        }.filter { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }

        // The last known fix answers at once; a fresh one follows when it comes in.
        providers.mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull { it.time }
            ?.let { send(device, it) }

        val provider = providers.firstOrNull() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            manager.getCurrentLocation(provider, null, worker) { location -> location?.let { send(device, it) } }
        } else {
            @Suppress("DEPRECATION")
            manager.requestSingleUpdate(provider, { send(device, it) }, Looper.getMainLooper())
        }
    }

    private fun send(device: Device, location: Location) {
        val found = PhoneLocation(location.latitude, location.longitude, location.accuracy.toDouble(), location.time)

        DeviceStore.send(device, found.toPacket())
    }
}
