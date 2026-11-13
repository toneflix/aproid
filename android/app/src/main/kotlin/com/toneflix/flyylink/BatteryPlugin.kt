package com.toneflix.flyylink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import com.toneflix.flyylink.protocol.BatteryStatus
import com.toneflix.flyylink.protocol.Device
import com.toneflix.flyylink.protocol.NetworkPacket
import com.toneflix.flyylink.protocol.PacketType
import com.toneflix.flyylink.protocol.Plugin

/** Sends the battery level to paired Macs whenever it changes. */
object BatteryPlugin : Plugin {
    override val incoming = setOf(PacketType.BATTERY_REQUEST)

    @Volatile private var current: BatteryStatus? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = read(intent) ?: return
            if (status == current) return

            current = status
            DeviceStore.sendToPaired(status.toPacket())
        }
    }

    fun start(context: Context) {
        // The battery broadcast is sticky, so registering also returns the current state.
        context.registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))?.let { current = read(it) }
    }

    fun stop(context: Context) {
        runCatching { context.unregisterReceiver(receiver) }
    }

    override fun onPaired(device: Device) {
        current?.let { DeviceStore.send(device, it.toPacket()) }
    }

    override fun onPacket(device: Device, packet: NetworkPacket) = onPaired(device)

    private fun read(intent: Intent): BatteryStatus? {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return null

        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0

        return BatteryStatus.of(charge = level * 100 / scale, isCharging = plugged)
    }
}
