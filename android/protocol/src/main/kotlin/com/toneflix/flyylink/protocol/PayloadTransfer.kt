package com.toneflix.flyylink.protocol

import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLSocket
import kotlin.concurrent.thread

/**
 * Moves a packet's payload, such as a file, over its own TLS connection, as KDE Connect does.
 * The sender opens a port and acts as the TLS server; the receiver connects as the client.
 * Each side checks the other's certificate against the one from the device link.
 */
class PayloadTransfer(certificate: DeviceCertificate, private val ports: IntRange = PAYLOAD_PORT_RANGE) {
    private val tls = TlsUpgrader(certificate)

    /**
     * Opens a port and streams the bytes from [open] to the first peer that connects with
     * [peerCertificate]. Returns the port to put in the packet.
     */
    fun offer(peerCertificate: X509Certificate, open: () -> InputStream, onDone: (Throwable?) -> Unit = {}): Int {
        val server = bind()
        server.soTimeout = ACCEPT_TIMEOUT_MS

        thread(name = "flyylink-upload", isDaemon = true) {
            val error = runCatching {
                server.use { it.accept() }.use { socket ->
                    secure(socket, asServer = true, peerCertificate).use { ssl ->
                        open().use { it.copyTo(ssl.outputStream, BUFFER_SIZE) }
                        ssl.outputStream.flush()
                    }
                }
            }.exceptionOrNull()

            onDone(error)
        }

        return server.localPort
    }

    /**
     * Downloads [size] bytes that the peer offered at [address]:[port] into [sink]. Blocks until done.
     * A size of [Screen.STREAM] reads a live stream until the peer closes it.
     */
    fun receive(address: InetAddress, port: Int, size: Long, peerCertificate: X509Certificate, sink: OutputStream) {
        Socket().use { socket ->
            socket.connect(InetSocketAddress(address, port), CONNECT_TIMEOUT_MS)
            socket.soTimeout = READ_TIMEOUT_MS

            secure(socket, asServer = false, peerCertificate).use { ssl ->
                val copied = copy(ssl.inputStream, sink, if (size == Screen.STREAM) Long.MAX_VALUE else size)
                if (size != Screen.STREAM && copied < size) throw ProtocolException("payload ended after $copied of $size bytes")
            }
        }
    }

    private fun secure(socket: Socket, asServer: Boolean, peerCertificate: X509Certificate): SSLSocket {
        socket.sendBufferSize = SOCKET_BUFFER
        socket.receiveBufferSize = SOCKET_BUFFER
        val ssl = tls.upgrade(socket, asServer)
        val presented = ssl.session.peerCertificates.firstOrNull() as? X509Certificate

        if (presented == null || !presented.encoded.contentEquals(peerCertificate.encoded)) {
            ssl.close()
            throw ProtocolException("payload peer is not the paired device")
        }

        return ssl
    }

    private fun copy(input: InputStream, sink: OutputStream, size: Long): Long {
        val buffer = ByteArray(BUFFER_SIZE)
        var copied = 0L

        while (copied < size) {
            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), size - copied).toInt())
            if (read < 0) break

            sink.write(buffer, 0, read)
            copied += read
        }
        sink.flush()

        return copied
    }

    private fun bind(): ServerSocket {
        for (port in ports) {
            try {
                return ServerSocket().apply {
                    reuseAddress = true
                    bind(InetSocketAddress(port))
                }
            } catch (_: SocketException) {
                continue
            }
        }

        throw ProtocolException("no free payload port in $ports")
    }

    private companion object {
        const val ACCEPT_TIMEOUT_MS = 60_000
        const val CONNECT_TIMEOUT_MS = 10_000
        const val READ_TIMEOUT_MS = 30_000
        // Large reads and socket buffers keep a fast Wi-Fi link full instead of waiting on small writes.
        const val BUFFER_SIZE = 256 * 1024
        const val SOCKET_BUFFER = 1024 * 1024
    }
}
