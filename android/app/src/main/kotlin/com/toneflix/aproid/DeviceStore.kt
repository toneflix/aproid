package com.toneflix.aproid

import android.content.Context
import android.os.Build
import android.util.Log
import android.util.Base64
import com.toneflix.aproid.protocol.Device
import com.toneflix.aproid.protocol.DeviceCertificate
import com.toneflix.aproid.protocol.DeviceIdentity
import com.toneflix.aproid.protocol.DeviceLink
import com.toneflix.aproid.protocol.DeviceType
import com.toneflix.aproid.protocol.NetworkPacket
import com.toneflix.aproid.protocol.PairState
import com.toneflix.aproid.protocol.PluginRouter
import com.toneflix.aproid.protocol.TrustStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.util.concurrent.Executors

/** What the UI shows for one connected device. */
data class DeviceState(
    val id: String,
    val name: String,
    val type: DeviceType,
    val address: String,
    val pairState: PairState,
    val code: String?,
)

/** This phone's identity and certificate, trusted devices, and the devices connected now. */
object DeviceStore {
    private const val TAG = "AproidLink"
    private const val PREFS = "aproid"
    private const val TRUST_PREFS = "aproid_trusted"
    private const val KEY_ID = "device_id"

    private val devices = linkedMapOf<String, Device>()

    private val plugins = PluginRouter(listOf(NotificationPlugin, BatteryPlugin, FindMyPhonePlugin, ClipboardPlugin))

    /** Network writes must stay off the main thread, so all plugin sends go through here. */
    private val sender = Executors.newSingleThreadExecutor()

    private val _states = MutableStateFlow<List<DeviceState>>(emptyList())
    val states: StateFlow<List<DeviceState>> = _states.asStateFlow()

    private val _pairRequest = MutableStateFlow<DeviceState?>(null)

    /** A device waiting for the user to accept or reject pairing. */
    val pairRequest: StateFlow<DeviceState?> = _pairRequest.asStateFlow()

    val listener = object : Device.Listener {
        override fun onPairRequest(device: Device, code: String) {
            _pairRequest.value = device.toState()
            publish()
        }

        override fun onPairStateChanged(device: Device, state: PairState) {
            if (state != PairState.REQUESTED_BY_PEER && _pairRequest.value?.id == device.id) {
                _pairRequest.value = null
            }
            if (state == PairState.PAIRED) plugins.onPaired(device)
            publish()
        }

        override fun onPacket(device: Device, packet: NetworkPacket) {
            plugins.dispatch(device, packet)
        }

        override fun onDisconnected(device: Device) = remove(device)
    }

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

    /** Loads the certificate from app storage, creating it on first launch. */
    fun certificate(context: Context): DeviceCertificate {
        val certFile = File(context.filesDir, "device.crt")
        val keyFile = File(context.filesDir, "device.key")

        val deviceId = identity(context).deviceId

        // Reuse the stored certificate only if it belongs to this device id. Peers refuse
        // a certificate whose common name differs from the id we announce.
        if (certFile.exists() && keyFile.exists()) {
            val stored = runCatching { DeviceCertificate.load(certFile.readBytes(), keyFile.readBytes()) }.getOrNull()
            if (stored != null && stored.deviceId == deviceId) return stored
        }

        val certificate = DeviceCertificate.generate(deviceId)
        certFile.writeBytes(certificate.encodedCertificate)
        keyFile.writeBytes(certificate.encodedPrivateKey)

        return certificate
    }

    fun trustStore(context: Context): TrustStore = PreferencesTrustStore(context.applicationContext)

    @Synchronized fun add(device: Device, ownDeviceId: String) {
        val existing = devices[device.id]
        if (existing != null && DeviceLink.keepsExisting(existing.link, device.link, ownDeviceId)) {
            device.link.close("both sides connected at once; kept the other link")
            return
        }

        existing?.link?.close("replaced by a newer link")
        devices[device.id] = device
        Log.i(TAG, "Connected to ${device.name} (${if (device.link.isOutgoing) "we" else "they"} connected)")
        device.listener = listener
        device.start()
        if (device.isPaired) plugins.onPaired(device)
        publish()
    }

    fun send(device: Device, packet: NetworkPacket) {
        sender.execute { runCatching { device.send(packet) } }
    }

    fun sendToPaired(packet: NetworkPacket) {
        val targets = synchronized(this) { devices.values.filter { it.isPaired } }

        targets.forEach { send(it, packet) }
    }

    @Synchronized fun remove(device: Device) {
        Log.i(TAG, "Disconnected from ${device.name}: ${device.link.closeReason}")
        if (devices[device.id] === device) devices.remove(device.id)
        if (_pairRequest.value?.id == device.id) _pairRequest.value = null
        publish()
    }

    @Synchronized fun find(id: String): Device? = devices[id]

    @Synchronized fun tickAll() = devices.values.forEach { it.tick() }

    @Synchronized fun clear() {
        devices.values.toList().forEach { it.link.close() }
        devices.clear()
        _pairRequest.value = null
        publish()
    }

    @Synchronized private fun publish() {
        _states.value = devices.values.map { it.toState() }
    }

    private fun Device.toState() = DeviceState(
        id = id,
        name = name,
        type = link.identity.deviceType,
        address = link.address.hostAddress ?: "",
        pairState = pairState,
        code = if (pairState == PairState.REQUESTED || pairState == PairState.REQUESTED_BY_PEER) verificationCode else null,
    )

    private class PreferencesTrustStore(context: Context) : TrustStore {
        private val prefs = context.getSharedPreferences(TRUST_PREFS, Context.MODE_PRIVATE)

        override fun certificate(deviceId: String): ByteArray? =
            prefs.getString(deviceId, null)?.let { Base64.decode(it, Base64.NO_WRAP) }

        override fun trust(deviceId: String, encodedCertificate: ByteArray) {
            prefs.edit().putString(deviceId, Base64.encodeToString(encodedCertificate, Base64.NO_WRAP)).apply()
        }

        override fun forget(deviceId: String) {
            prefs.edit().remove(deviceId).apply()
        }
    }
}
