package com.toneflix.aproid.protocol

import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

/** A peer we found on the network and exchanged identities with. */
data class DiscoveredPeer(val identity: DeviceIdentity, val address: InetAddress)

/**
 * LAN discovery and the plain-text identity exchange from the KDE Connect protocol.
 *
 * 1. We broadcast our identity over UDP to port 1716.
 * 2. A peer that hears it opens a TCP connection to our tcpPort and sends its identity.
 * 3. Both sides then upgrade the socket to TLS (not done here yet: see docs/ARCHITECTURE.md).
 *
 * Plain java.net so it runs on Android and in JVM tests.
 */
class LanLink(
    private val identityProvider: () -> DeviceIdentity,
    private val onPeer: (DiscoveredPeer, Socket) -> Unit,
    private val udpPort: Int = UDP_PORT,
    private val tcpPorts: IntRange = TCP_PORT_RANGE,
) {
    @Volatile private var running = false
    private var server: ServerSocket? = null
    private var udp: DatagramSocket? = null

    /** Port the TCP listener is bound to, once started. */
    val tcpPort: Int? get() = server?.localPort

    fun start() {
        if (running) return
        running = true
        server = bindTcp()
        thread(name = "aproid-tcp", isDaemon = true) { acceptLoop() }
        try {
            udp = DatagramSocket(null).apply {
                reuseAddress = true
                broadcast = true
                bind(InetSocketAddress(udpPort))
            }
            thread(name = "aproid-udp", isDaemon = true) { udpLoop() }
        } catch (e: SocketException) {
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

    /** Send our identity to everyone on the local network. */
    fun broadcastIdentity(target: InetAddress = InetAddress.getByName("255.255.255.255")) {
        val bytes = currentIdentity().toPacket().serialize().toByteArray(StandardCharsets.UTF_8)
        DatagramSocket().use { s ->
            s.broadcast = true
            s.send(DatagramPacket(bytes, bytes.size, target, udpPort))
        }
    }

    /** Connect to a peer that announced itself, and send our identity. */
    fun connect(peer: DeviceIdentity, address: InetAddress) {
        val port = peer.tcpPort ?: throw ProtocolException("peer did not send tcpPort")
        val socket = Socket()
        socket.connect(InetSocketAddress(address, port), 5_000)
        socket.getOutputStream().apply {
            write(currentIdentity().toPacket().serialize().toByteArray(StandardCharsets.UTF_8))
            flush()
        }
        onPeer(DiscoveredPeer(peer, address), socket)
    }

    private fun currentIdentity(): DeviceIdentity = identityProvider().copy(tcpPort = tcpPort)

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
            thread(name = "aproid-handshake", isDaemon = true) {
                try {
                    socket.soTimeout = 10_000
                    val reader = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
                    val line = reader.readLine() ?: throw ProtocolException("closed before identity")
                    val identity = DeviceIdentity.fromPacket(NetworkPacket.parse(line))
                    if (identity.deviceId == identityProvider().deviceId) {
                        socket.close()
                    } else {
                        socket.soTimeout = 0
                        onPeer(DiscoveredPeer(identity, socket.inetAddress), socket)
                    }
                } catch (_: Exception) {
                    socket.close()
                }
            }
        }
    }

    private fun udpLoop() {
        val sock = udp ?: return
        val buf = ByteArray(64 * 1024)
        while (running) {
            val dp = DatagramPacket(buf, buf.size)
            try { sock.receive(dp) } catch (_: SocketException) { break }
            try {
                val text = String(dp.data, dp.offset, dp.length, StandardCharsets.UTF_8)
                val identity = DeviceIdentity.fromPacket(NetworkPacket.parse(text))
                if (identity.deviceId != identityProvider().deviceId) {
                    thread(isDaemon = true) { runCatching { connect(identity, dp.address) } }
                }
            } catch (_: Exception) {
                // Ignore anything that is not a valid identity.
            }
        }
    }
}
