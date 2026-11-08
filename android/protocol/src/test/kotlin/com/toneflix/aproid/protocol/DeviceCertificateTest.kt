package com.toneflix.aproid.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class DeviceCertificateTest {
    @Test fun commonNameIsDeviceId() {
        val id = DeviceIdentity.newDeviceId()
        val cert = DeviceCertificate.generate(id)

        assertEquals(id, cert.deviceId)
    }

    @Test fun survivesStorage() {
        val cert = DeviceCertificate.generate(DeviceIdentity.newDeviceId())

        val loaded = DeviceCertificate.load(cert.encodedCertificate, cert.encodedPrivateKey)

        assertArrayEquals(cert.encodedCertificate, loaded.encodedCertificate)
        assertArrayEquals(cert.encodedPrivateKey, loaded.encodedPrivateKey)
    }

    @Test fun verificationKeyIsTheSameOnBothSides() {
        val a = DeviceCertificate.generate(DeviceIdentity.newDeviceId()).publicKeyBytes
        val b = DeviceCertificate.generate(DeviceIdentity.newDeviceId()).publicKeyBytes

        val code = VerificationKey.compute(a, b, 1_700_000_000)

        assertEquals(code, VerificationKey.compute(b, a, 1_700_000_000))
        assertEquals(8, code.length)
        assertEquals(code.uppercase(), code)
        assertNotEquals(code, VerificationKey.compute(a, b, 1_700_000_001))
    }

    /** Same inputs as the Swift side must give the same code. */
    @Test fun verificationKeyMatchesSwift() {
        val code = VerificationKey.compute(byteArrayOf(1, 2, 3), byteArrayOf(0xFF.toByte()), 42)

        assertEquals("89CE2D9C", code)
    }
}
