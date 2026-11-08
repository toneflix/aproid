package com.toneflix.aproid

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import com.toneflix.aproid.protocol.DeviceCertificate
import com.toneflix.aproid.protocol.Nearby
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Lets a paired Mac find the phone over Bluetooth when Wi-Fi discovery fails, such as on a network
 * that blocks broadcasts or when they share no network at all. The Mac asks; the phone answers with
 * its address, and on request starts a local hotspot the Mac can join. Answers are sealed to the
 * asking Mac's certificate, so nobody else nearby can read them.
 */
@SuppressLint("MissingPermission")
class NearbyBeacon(private val context: Context, private val port: () -> Int?) {
    private val bluetooth = context.getSystemService(BluetoothManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var server: BluetoothGattServer? = null
    private var hotspot: WifiManager.LocalOnlyHotspotReservation? = null

    /** The sealed answer waiting for each Mac to read. */
    private val answers = ConcurrentHashMap<String, ByteArray>()

    private val serviceId = UUID.fromString(Nearby.SERVICE)
    private val requestId = UUID.fromString(Nearby.REQUEST)
    private val answerId = UUID.fromString(Nearby.ANSWER)
    private val notifyConfigId = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    fun start() {
        if (!hasPermission(context) || server != null) return
        val adapter = bluetooth?.adapter?.takeIf { it.isEnabled } ?: return

        val service = BluetoothGattService(serviceId, BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
            addCharacteristic(
                BluetoothGattCharacteristic(
                    requestId,
                    BluetoothGattCharacteristic.PROPERTY_WRITE,
                    BluetoothGattCharacteristic.PERMISSION_WRITE,
                ),
            )
            addCharacteristic(
                BluetoothGattCharacteristic(
                    answerId,
                    BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                    BluetoothGattCharacteristic.PERMISSION_READ,
                ).apply {
                    addDescriptor(
                        BluetoothGattDescriptor(
                            notifyConfigId,
                            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
                        ),
                    )
                },
            )
        }

        server = runCatching { bluetooth?.openGattServer(context, callback)?.apply { addService(service) } }.getOrNull()
        if (server == null) return

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .build()
        val data = AdvertiseData.Builder().addServiceUuid(ParcelUuid(serviceId)).build()
        runCatching { adapter.bluetoothLeAdvertiser?.startAdvertising(settings, data, advertising) }
    }

    fun stop() {
        runCatching { bluetooth?.adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertising) }
        runCatching { server?.close() }
        server = null
        hotspot?.close()
        hotspot = null
        answers.clear()
    }

    private val advertising = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            Log.w(TAG, "Bluetooth advertising failed: $errorCode")
        }
    }

    private val callback = object : BluetoothGattServerCallback() {
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            val accepted = characteristic.uuid == this@NearbyBeacon.requestId && value != null
            if (responseNeeded) {
                server?.sendResponse(device, requestId, if (accepted) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE, offset, null)
            }

            val request = value?.takeIf { accepted }?.let(Nearby.Request::fromBytes) ?: return
            worker.execute { answer(device, request) }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) {
            // Long answers are read in pieces, each starting at [offset].
            val answer = answers[device.address] ?: ByteArray(0)
            val piece = if (offset < answer.size) answer.copyOfRange(offset, answer.size) else ByteArray(0)
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, piece)
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
        }
    }

    /** Only Macs we trust get an answer, and only they can read it. */
    private fun answer(device: BluetoothDevice, request: Nearby.Request) {
        val trusted = DeviceStore.trustStore(context).certificate(request.deviceId) ?: return
        val macKey = runCatching { DeviceCertificate.parse(trusted).publicKey }.getOrNull() ?: return
        val port = port() ?: return
        val ownId = DeviceStore.identity(context).deviceId

        fun reply(ssid: String? = null, password: String? = null) {
            val answer = Nearby.Answer(ownId, addresses(), port, ssid, password)
            answers[device.address] = Nearby.seal(answer, macKey)
            notifyReady(device)
        }

        if (request.want == Nearby.Want.CONNECT) {
            reply()
            return
        }

        startHotspot { ssid, password ->
            // The hotspot's own address shows up a moment after it starts.
            main.postDelayed({ worker.execute { reply(ssid, password) } }, 1000)
        }
    }

    /** Tells the Mac its answer is ready to read. */
    private fun notifyReady(device: BluetoothDevice) {
        val server = server ?: return
        val characteristic = server.getService(serviceId)?.getCharacteristic(answerId) ?: return
        val ready = byteArrayOf(1)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            server.notifyCharacteristicChanged(device, characteristic, false, ready)
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = ready
            @Suppress("DEPRECATION")
            server.notifyCharacteristicChanged(device, characteristic, false)
        }
    }

    /**
     * Starts a hotspot only the Mac will use. Android doesn't let apps turn on the normal hotspot,
     * but any app may start this local one. [onReady] gets nulls if the phone can't start it.
     */
    private fun startHotspot(onReady: (String?, String?) -> Unit) {
        hotspot?.let {
            val (ssid, password) = credentials(it)
            onReady(ssid, password)
            return
        }

        val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
        main.post {
            runCatching {
                wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                        hotspot = reservation
                        val (ssid, password) = credentials(reservation)
                        onReady(ssid, password)
                    }

                    override fun onFailed(reason: Int) {
                        Log.w(TAG, "Local hotspot failed: $reason")
                        onReady(null, null)
                    }
                }, main)
            }.onFailure {
                Log.w(TAG, "Local hotspot not allowed", it)
                onReady(null, null)
            }
        }
    }

    private fun credentials(reservation: WifiManager.LocalOnlyHotspotReservation): Pair<String?, String?> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = reservation.softApConfiguration
            val ssid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                config.wifiSsid?.toString()?.removeSurrounding("\"")
            } else {
                @Suppress("DEPRECATION")
                config.ssid
            }
            ssid to config.passphrase
        } else {
            @Suppress("DEPRECATION")
            val config = reservation.wifiConfiguration
            @Suppress("DEPRECATION")
            config?.SSID?.removeSurrounding("\"") to config?.preSharedKey?.removeSurrounding("\"")
        }

    /** This phone's IPv4 addresses on every network it's on, the hotspot included. */
    private fun addresses(): List<String> = runCatching {
        NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { it.inetAddresses.toList() }
            .filterIsInstance<Inet4Address>()
            .mapNotNull { it.hostAddress }
            .take(4)
    }.getOrDefault(emptyList())

    companion object {
        private const val TAG = "AproidNearby"

        val permissions: Array<String> = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_ADVERTISE)
                add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.NEARBY_WIFI_DEVICES)
            } else {
                add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }.toTypedArray()

        fun hasPermission(context: Context) =
            permissions.all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    }
}
