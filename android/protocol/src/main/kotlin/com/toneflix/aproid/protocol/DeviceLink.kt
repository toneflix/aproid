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
) : Closeable {
    var onPacket: ((NetworkPacket) -> Unit)? = null
    var onClosed: (() -> Unit)? = null

    @Volatile var isOpen: Boolean = true
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
            try {
                while (isOpen) {
                    val line = reader.readLine() ?: break
                    if (line.isBlank()) continue

                    val packet = runCatching { NetworkPacket.parse(line) }.getOrNull() ?: continue
                    onPacket?.invoke(packet)
                }
            } catch (_: Exception) {
                // Socket closed or broken: handled below.
            }

            close()
        }
    }

    override fun close() {
        if (!isOpen) return

        isOpen = false
        runCatching { socket.close() }
        onClosed?.invoke()
    }
}
