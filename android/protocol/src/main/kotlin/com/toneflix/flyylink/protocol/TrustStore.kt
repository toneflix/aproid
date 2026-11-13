package com.toneflix.flyylink.protocol

import java.util.concurrent.ConcurrentHashMap

/** Certificates of paired devices, by device id. */
interface TrustStore {
    fun certificate(deviceId: String): ByteArray?

    fun trust(deviceId: String, encodedCertificate: ByteArray)

    fun forget(deviceId: String)

    fun isTrusted(deviceId: String): Boolean = certificate(deviceId) != null
}

class InMemoryTrustStore : TrustStore {
    private val certificates = ConcurrentHashMap<String, ByteArray>()

    override fun certificate(deviceId: String): ByteArray? = certificates[deviceId]

    override fun trust(deviceId: String, encodedCertificate: ByteArray) {
        certificates[deviceId] = encodedCertificate
    }

    override fun forget(deviceId: String) {
        certificates.remove(deviceId)
    }
}
