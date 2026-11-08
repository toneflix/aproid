package com.toneflix.aproid.protocol

import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x500.style.BCStyle
import org.bouncycastle.asn1.x500.style.IETFUtils
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Date

/**
 * This device's self-signed certificate. The common name is the device id,
 * which is how KDE Connect ties a TLS session to an identity.
 */
class DeviceCertificate private constructor(
    val certificate: X509Certificate,
    val privateKey: PrivateKey,
) {
    val deviceId: String? get() = commonName(certificate)

    val publicKeyBytes: ByteArray get() = certificate.publicKey.encoded

    val encodedCertificate: ByteArray get() = certificate.encoded

    /** PKCS#8 bytes, for storage. */
    val encodedPrivateKey: ByteArray get() = privateKey.encoded

    companion object {
        private const val VALID_DAYS = 3650L

        fun generate(deviceId: String, now: Instant = Instant.now()): DeviceCertificate {
            val keys = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
            val name = X500Name("CN=$deviceId,O=KDE,OU=KDE Connect")

            val builder = JcaX509v3CertificateBuilder(
                name,
                BigInteger.valueOf(now.toEpochMilli()),
                Date.from(now.minus(1, ChronoUnit.DAYS)),
                Date.from(now.plus(VALID_DAYS, ChronoUnit.DAYS)),
                name,
                keys.public,
            )
            val signer = JcaContentSignerBuilder("SHA256withRSA").build(keys.private)
            val certificate = JcaX509CertificateConverter().getCertificate(builder.build(signer))

            return DeviceCertificate(certificate, keys.private)
        }

        fun load(encodedCertificate: ByteArray, encodedPrivateKey: ByteArray): DeviceCertificate {
            val key = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(encodedPrivateKey))

            return DeviceCertificate(parse(encodedCertificate), key)
        }

        fun parse(encoded: ByteArray): X509Certificate =
            CertificateFactory.getInstance("X.509").generateCertificate(encoded.inputStream()) as X509Certificate

        fun commonName(certificate: X509Certificate): String? {
            val name = X500Name.getInstance(certificate.subjectX500Principal.encoded)
            val rdn = name.getRDNs(BCStyle.CN).firstOrNull() ?: return null

            return IETFUtils.valueToString(rdn.first.value)
        }
    }
}
