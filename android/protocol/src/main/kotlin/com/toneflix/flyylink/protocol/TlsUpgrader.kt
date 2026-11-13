package com.toneflix.flyylink.protocol

import java.net.Socket
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.KeyManager
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509TrustManager

/**
 * Turns a connected socket into TLS, as KDE Connect does after the plain-text identity.
 *
 * Every device uses a self-signed certificate, so the handshake accepts any certificate
 * and [LanLink] checks it afterwards against the device id and the trust store.
 */
class TlsUpgrader(certificate: DeviceCertificate) {
    private val keyManagers: Array<KeyManager>
    private val server: SSLContext

    init {
        val password = CharArray(0)
        val keyStore = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            load(null, null)
            setKeyEntry("device", certificate.privateKey, password, arrayOf(certificate.certificate))
        }
        keyManagers = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
            .apply { init(keyStore, password) }
            .keyManagers
        server = newContext()
    }

    /**
     * The side that opened the TCP connection is the TLS server. The client side never resumes a session,
     * so the peer always sees our certificate.
     */
    fun upgrade(socket: Socket, asServer: Boolean): SSLSocket {
        val host = socket.inetAddress.hostAddress
        val context = if (asServer) server else newContext()
        val ssl = context.socketFactory.createSocket(socket, host, socket.port, true) as SSLSocket

        ssl.useClientMode = !asServer
        if (asServer) ssl.needClientAuth = true
        ssl.startHandshake()

        return ssl
    }

    // Each context keeps its own session cache, so a fresh one has nothing to resume.
    private fun newContext(): SSLContext = SSLContext.getInstance("TLS").apply {
        init(keyManagers, arrayOf(AcceptAnyCertificate), SecureRandom())
    }

    private object AcceptAnyCertificate : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }
}
