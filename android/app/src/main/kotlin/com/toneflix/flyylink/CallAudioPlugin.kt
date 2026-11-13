package com.toneflix.flyylink

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.toneflix.flyylink.protocol.CallAudio
import com.toneflix.flyylink.protocol.Device
import com.toneflix.flyylink.protocol.NetworkPacket
import com.toneflix.flyylink.protocol.PacketType
import com.toneflix.flyylink.protocol.Plugin
import java.util.concurrent.ConcurrentHashMap

/**
 * The phone's side of call audio on the Mac. The Mac joins as a Bluetooth hands-free device, and Android
 * then sends call audio to it by itself. This reports the Bluetooth link to the Mac and pairs with it when asked.
 */
object CallAudioPlugin : Plugin {
    private const val TAG = "FlyyLinkCallAudio"

    override val incoming = setOf(PacketType.CALL_AUDIO_REQUEST)

    private var context: Context? = null
    @Volatile private var headset: BluetoothHeadset? = null

    /** Each Mac's Bluetooth address, by FlyyLink device id, so changes reach the Macs that asked. */
    private val macs = ConcurrentHashMap<String, String>()

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = reportAll()
    }

    private val headsetListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            headset = proxy as? BluetoothHeadset
            reportAll()
        }

        override fun onServiceDisconnected(profile: Int) {
            headset = null
        }
    }

    fun start(context: Context) {
        val app = context.applicationContext
        this.context = app

        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
        }
        app.registerReceiver(receiver, filter)
        openHeadsetProxy(app)
    }

    fun stop(context: Context) {
        runCatching { context.applicationContext.unregisterReceiver(receiver) }
        headset?.let { adapter(context)?.closeProfileProxy(BluetoothProfile.HEADSET, it) }
        headset = null
    }

    override fun onPacket(device: Device, packet: NetworkPacket) {
        val context = context ?: return
        val request = CallAudio.request(packet) ?: return

        macs[device.id] = request.address
        if (request.action == CallAudio.Action.PAIR) pair(context, request.address)
        if (headset == null) openHeadsetProxy(context)

        DeviceStore.send(device, CallAudio.status(status(context, request.address)))
    }

    private fun reportAll() {
        val context = context ?: return

        macs.forEach { (deviceId, address) ->
            DeviceStore.find(deviceId)?.let { DeviceStore.send(it, CallAudio.status(status(context, address))) }
        }
    }

    @SuppressLint("MissingPermission")
    private fun status(context: Context, address: String): CallAudio.Status {
        val adapter = adapter(context)
        val isOn = runCatching { adapter?.isEnabled == true }.getOrDefault(false)
        if (adapter == null || !isOn || !allowed(context)) {
            return CallAudio.Status(bluetoothOn = isOn, allowed = allowed(context), paired = false, connected = false)
        }

        return runCatching {
            val mac = adapter.getRemoteDevice(address)
            val paired = mac.bondState == BluetoothDevice.BOND_BONDED
            val connected = headset?.getConnectionState(mac) == BluetoothProfile.STATE_CONNECTED

            CallAudio.Status(bluetoothOn = true, allowed = true, paired = paired, connected = connected, name = adapter.name)
        }.getOrElse {
            Log.w(TAG, "Couldn't read the Bluetooth link", it)
            CallAudio.Status(bluetoothOn = true, allowed = true, paired = false, connected = false)
        }
    }

    /** Starts pairing with the Mac. Both screens then show the same code to confirm. */
    @SuppressLint("MissingPermission")
    private fun pair(context: Context, address: String) {
        val adapter = adapter(context) ?: return
        if (!allowed(context) || !adapter.isEnabled) return

        runCatching {
            val mac = adapter.getRemoteDevice(address)
            if (mac.bondState == BluetoothDevice.BOND_NONE) mac.createBond()
        }.onFailure { Log.w(TAG, "Pairing with the Mac failed", it) }
    }

    private fun openHeadsetProxy(context: Context) {
        if (!allowed(context)) return

        runCatching { adapter(context)?.getProfileProxy(context, headsetListener, BluetoothProfile.HEADSET) }
            .onFailure { Log.w(TAG, "No headset profile", it) }
    }

    private fun adapter(context: Context): BluetoothAdapter? = context.getSystemService(BluetoothManager::class.java)?.adapter

    private fun allowed(context: Context) = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
}
