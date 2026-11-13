package com.toneflix.flyylink.protocol

import java.security.MessageDigest

/**
 * The short code both screens show while pairing. It is a SHA-256 over both
 * public keys (larger first, compared as unsigned bytes) and the pair request
 * timestamp, cut to 8 hex characters.
 */
object VerificationKey {
    fun compute(publicKeyA: ByteArray, publicKeyB: ByteArray, timestamp: Long): String {
        val (first, second) = if (compareUnsigned(publicKeyA, publicKeyB) >= 0) {
            publicKeyA to publicKeyB
        } else {
            publicKeyB to publicKeyA
        }

        val digest = MessageDigest.getInstance("SHA-256").run {
            update(first)
            update(second)
            update(timestamp.toString().toByteArray(Charsets.UTF_8))
            digest()
        }

        return digest.joinToString("") { "%02x".format(it) }.take(8).uppercase()
    }

    private fun compareUnsigned(a: ByteArray, b: ByteArray): Int {
        for (i in 0 until minOf(a.size, b.size)) {
            val diff = (a[i].toInt() and 0xff) - (b[i].toInt() and 0xff)
            if (diff != 0) return diff
        }

        return a.size - b.size
    }
}
