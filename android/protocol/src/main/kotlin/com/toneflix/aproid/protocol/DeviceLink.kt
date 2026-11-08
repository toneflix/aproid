package com.toneflix.aproid.protocol

import java.io.BufferedReader
import java.io.Closeable
import java.io.InputStreamReader
import java.net.InetAddress
import java.nio.charset.StandardCharsets
import java.security.cert.X509Certificate
import javax.net.ssl.SSLSocket
import kotlin.concurrent.thread

/** An encrypted connection to one peer. */
class DeviceLink(
    val identity: DeviceIdentity,
    val certificate: X509Certificate,
    val address: InetAddress,
    private val socket: SSLSocket,
    private val reader: BufferedReader = BufferedReader(InputStreamReader(socket.inputStream, StandardCharsets.UTF_8)),
    /** True when we opened the TCP connection. */
    val isOutgoing: Boolean = false,
    val openedAt: Long = System.currentTimeMillis(),
) : Closeable {
    var onPacket: ((NetworkPacket) -> Unit)? = null
    var onClosed: (() -> Unit)? = null

    @Volatile var isOpen: Boolean = true
        private set

    /** Why the link closed, for logs. */
    @Volatile var closeReason: String? = null
        private set

    fun send(packet: NetworkPacket) {
        val bytes = packet.serialize().toByteArray(StandardCharsets.UTF_8)

        synchronized(this) {
            socket.outputStream.write(bytes)
            socket.outputStream.flush()
        }
    }

    fun startReading() {
        thread(name = "aproid-link-${identity.deviceId.take(8)}", isDaemon = true) {
            val reason = try {
                while (isOpen) {
                    val line = reader.readLine() ?: break
                    if (line.isBlank()) continue

                    val packet = runCatching { NetworkPacket.parse(line) }.getOrNull() ?: continue
                    onPacket?.invoke(packet)
                }
                "peer closed the connection"
            } catch (e: Exception) {
                "read failed: $e"
            }

            close(reason)
        }
    }

    /** Who opened the TCP connection: us or the peer. */
    fun openerId(ownDeviceId: String): String = if (isOutgoing) ownDeviceId else identity.deviceId

    override fun close() = close("closed locally")

    fun close(reason: String) {
        if (!isOpen) return

        isOpen = false
        closeReason = reason
        runCatching { socket.close() }
        onClosed?.invoke()
    }

    companion object {
        /** Links opened this close together are two sides connecting at the same moment. */
        const val RACE_WINDOW_MS = 3_000L

        /**
         * Decides which link to keep when a second one to the same device arrives.
         *
         * If both sides connected at the same moment, both must keep the same TCP connection,
         * so the one opened by the device with the larger id wins. Otherwise the new link wins,
         * because a peer only reconnects when its old link has died.
         */
        fun keepsExisting(existing: DeviceLink, new: DeviceLink, ownDeviceId: String): Boolean {
            if (!existing.isOpen) return false
            if (Math.abs(new.openedAt - existing.openedAt) > RACE_WINDOW_MS) return false

            return existing.openerId(ownDeviceId) > new.openerId(ownDeviceId)
        }
    }
}
