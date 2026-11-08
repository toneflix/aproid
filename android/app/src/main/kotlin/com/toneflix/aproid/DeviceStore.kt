package com.toneflix.aproid

import android.content.Context
import android.os.Build
import com.toneflix.aproid.protocol.DeviceIdentity
import com.toneflix.aproid.protocol.DeviceType
import com.toneflix.aproid.protocol.DiscoveredPeer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** This phone's identity (kept across launches) and the devices found so far. */
object DeviceStore {
    private const val PREFS = "aproid"
    private const val KEY_ID = "device_id"

    private val _peers = MutableStateFlow<Map<String, DiscoveredPeer>>(emptyMap())
    val peers: StateFlow<Map<String, DiscoveredPeer>> = _peers.asStateFlow()

    fun identity(context: Context): DeviceIdentity {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val id = prefs.getString(KEY_ID, null) ?: DeviceIdentity.newDeviceId().also {
            prefs.edit().putString(KEY_ID, it).apply()
        }
        return DeviceIdentity(
            deviceId = id,
            deviceName = DeviceIdentity.sanitizeName(Build.MODEL ?: "Android"),
            deviceType = DeviceType.PHONE,
        )
    }

    fun onPeer(peer: DiscoveredPeer) {
        _peers.update { it + (peer.identity.deviceId to peer) }
    }

    fun clear() {
        _peers.value = emptyMap()
    }
}
