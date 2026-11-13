package com.toneflix.flyylink.protocol

import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.nio.charset.StandardCharsets
import java.security.cert.X509Certificate
import javax.net.ssl.SSLSocket
import kotlin.concurrent.thread

/**
 * LAN discovery and connection setup from the KDE Connect protocol.
 *
 * 1. We broadcast our identity over UDP to port 1716.
 * 2. A peer that hears it opens a TCP connection to our tcpPort and sends its identity.
 * 3. The socket is upgraded to TLS. The side that opened the TCP connection is the TLS server.
 * 4. With protocol v8, both sides send their identity again over TLS.
 *
 * Plain java.net so it runs on Android and in JVM tests.
 */
class LanLink(
    private val identityProvider: () -> DeviceIdentity,
    private val certificate: DeviceCertificate,
    private val trustStore: TrustStore,
    private val onLink: (DeviceLink) -> Unit,
    private val udpPort: Int = UDP_PORT,
    private val tcpPorts: IntRange = TCP_PORT_RANGE,
    private val isConnected: (deviceId: String) -> Boolean = { false },
) {
    private val tls = TlsUpgrader(certificate)

    @Volatile private var running = false
    private var server: ServerSocket? = null
    private var udp: DatagramSocket? = null

    /** Port the TCP listener is bound to, once started. */
    val tcpPort: Int? get() = server?.localPort

    fun start() {
        if (running) return

        running = true
        server = bindTcp()
        thread(name = "flyylink-tcp", isDaemon = true) { acceptLoop() }

        try {
            udp = DatagramSocket(null).apply {
                reuseAddress = true
                broadcast = true
                bind(InetSocketAddress(udpPort))
            }
            thread(name = "flyylink-udp", isDaemon = true) { udpLoop() }
        } catch (_: SocketException) {
            // Another app (for example KDE Connect itself) may own the port. TCP still works.
            udp = null
        }
    }

    fun stop() {
        running = false
        server?.close()
        udp?.close()
        server = null
        udp = null
    }

    /**
     * Sends our identity to everyone on the local network: to 255.255.255.255 and to each network's own
     * broadcast address, so it also reaches networks that aren't the default route, such as the phone's
     * own hotspot. Throws only when no copy could be sent.
     */
    fun broadcastIdentity(target: InetAddress? = null) {
        val bytes = currentIdentity().announcement().serialize().toByteArray(StandardCharsets.UTF_8)
        val targets = target?.let(::listOf) ?: broadcastAddresses()

        DatagramSocket().use { socket ->
            socket.broadcast = true

            val results = targets.map { runCatching { socket.send(DatagramPacket(bytes, bytes.size, it, udpPort)) } }
            if (results.none { it.isSuccess }) results.first().getOrThrow()
        }
    }

    /** Connect to a peer that announced itself. */
    fun connect(peer: DeviceIdentity, address: InetAddress): DeviceLink {
        val port = peer.tcpPort ?: throw ProtocolException("peer did not send tcpPort")
        val socket = Socket()

        try {
            socket.connect(InetSocketAddress(address, port), 5_000)
            socket.soTimeout = 10_000
            socket.getOutputStream().apply {
                write(currentIdentity().toPacket().serialize().toByteArray(StandardCharsets.UTF_8))
                flush()
            }

            val link = secure(socket, peer, asServer = true)
            onLink(link)

            return link
        } catch (e: Exception) {
            socket.close()
            throw e
        }
    }

    /**
     * Connects to a peer that announced itself over UDP, unless we already have a link to it.
     * Peers announce every few seconds, and reconnecting each time would drop the working link.
     */
    fun handleAnnouncement(peer: DeviceIdentity, address: InetAddress): Boolean {
        if (peer.deviceId == identityProvider().deviceId || isConnected(peer.deviceId)) return false

        thread(isDaemon = true) { runCatching { connect(peer, address) } }

        return true
    }

    private fun currentIdentity(): DeviceIdentity = identityProvider().copy(tcpPort = tcpPort)

    private fun secure(socket: Socket, plainIdentity: DeviceIdentity, asServer: Boolean): DeviceLink {
        val ssl = tls.upgrade(socket, asServer)
        val peerCertificate = ssl.session.peerCertificates.first() as X509Certificate

        checkCertificate(plainIdentity.deviceId, peerCertificate)

        val reader = BufferedReader(InputStreamReader(ssl.inputStream, StandardCharsets.UTF_8))
        val identity = if (plainIdentity.protocolVersion >= 8) {
            exchangeIdentity(ssl, reader, plainIdentity.deviceId)
        } else {
            plainIdentity
        }
        // Clear the handshake timeout on both layers, or an idle link would drop after 10 seconds.
        socket.soTimeout = 0
        ssl.soTimeout = 0
        socket.keepAlive = true

        return DeviceLink(identity, peerCertificate, socket.inetAddress, ssl, reader, isOutgoing = asServer)
    }

    private fun checkCertificate(deviceId: String, certificate: X509Certificate) {
        if (DeviceCertificate.commonName(certificate) != deviceId) {
            throw ProtocolException("certificate does not match device id")
        }

        val trusted = trustStore.certificate(deviceId) ?: return
        if (!trusted.contentEquals(certificate.encoded)) {
            throw ProtocolException("certificate changed for a paired device")
        }
    }

    private fun exchangeIdentity(ssl: SSLSocket, reader: BufferedReader, expectedId: String): DeviceIdentity {
        ssl.outputStream.write(currentIdentity().toPacket().serialize().toByteArray(StandardCharsets.UTF_8))
        ssl.outputStream.flush()

        val line = reader.readLine() ?: throw ProtocolException("closed before encrypted identity")
        val identity = DeviceIdentity.fromPacket(NetworkPacket.parse(line))
        if (identity.deviceId != expectedId) throw ProtocolException("device id changed after TLS")

        return identity
    }

    private fun bindTcp(): ServerSocket {
        for (port in tcpPorts) {
            try {
                return ServerSocket().apply {
                    reuseAddress = true
                    bind(InetSocketAddress(port))
                }
            } catch (_: SocketException) {
                continue
            }
        }

        throw ProtocolException("no free TCP port in $tcpPorts")
    }

    private fun acceptLoop() {
        val srv = server ?: return

        while (running) {
            val socket = try { srv.accept() } catch (_: SocketException) { break }
            thread(name = "flyylink-handshake", isDaemon = true) { handleIncoming(socket) }
        }
    }

    private fun handleIncoming(socket: Socket) {
        try {
            socket.soTimeout = 10_000
            val identity = DeviceIdentity.fromPacket(NetworkPacket.parse(readPlainLine(socket)))

            if (identity.deviceId == identityProvider().deviceId) {
                socket.close()
                return
            }

            onLink(secure(socket, identity, asServer = false))
        } catch (_: Exception) {
            socket.close()
        }
    }

    /**
     * Reads the plain-text identity one byte at a time, so no TLS bytes that
     * follow it are swallowed by a buffer.
     */
    private fun readPlainLine(socket: Socket): String {
        val input = socket.getInputStream()
        val bytes = java.io.ByteArrayOutputStream()

        while (true) {
            val b = input.read()
            if (b == -1) throw ProtocolException("closed before identity")
            if (b == '\n'.code) break
            if (bytes.size() > 64 * 1024) throw ProtocolException("identity too long")
            bytes.write(b)
        }

        return bytes.toString(StandardCharsets.UTF_8.name())
    }

    private fun udpLoop() {
        val sock = udp ?: return
        val buf = ByteArray(64 * 1024)

        while (running) {
            val dp = DatagramPacket(buf, buf.size)
            try { sock.receive(dp) } catch (_: SocketException) { break }

            val identity = runCatching {
                DeviceIdentity.fromPacket(NetworkPacket.parse(String(dp.data, dp.offset, dp.length, StandardCharsets.UTF_8)))
            }.getOrNull() ?: continue

            handleAnnouncement(identity, dp.address)
        }
    }

    companion object {
        /** 255.255.255.255 plus the broadcast address of each IPv4 network this device is on. */
        fun broadcastAddresses(): List<InetAddress> {
            val addresses = linkedSetOf<InetAddress>(InetAddress.getByName("255.255.255.255"))

            runCatching {
                NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
                    .filter { it.isUp && !it.isLoopback }
                    .flatMap { it.interfaceAddresses }
                    .filter { it.address is Inet4Address }
                    .mapNotNullTo(addresses) { it.broadcast }
            }

            return addresses.toList()
        }
    }
}
