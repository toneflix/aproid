package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.security.KeyFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64

class NearbyTest {
    private val mac = DeviceCertificate.generate(DeviceIdentity.newDeviceId())
    private val answer = Nearby.Answer("a1b2c3d4e5f60718293a4b5c6d7e8f90", listOf("192.168.43.1"), 1716)

    @Test fun answerOpensOnlyWithTheRightKey() {
        val sealed = Nearby.seal(answer, mac.certificate.publicKey)
        val stranger = DeviceCertificate.generate(DeviceIdentity.newDeviceId())

        assertEquals(answer, Nearby.open(sealed, mac.privateKey))
        assertNull(Nearby.open(sealed, stranger.privateKey))
        assertNull(Nearby.open(sealed.copyOf().also { it[it.size - 1] = (it.last() + 1).toByte() }, mac.privateKey))
    }

    @Test fun requestRoundTrips() {
        val request = Nearby.Request(mac.deviceId!!, Nearby.Want.HOTSPOT)

        assertEquals(request, Nearby.Request.fromBytes(request.toBytes()))
        assertNull(Nearby.Request.fromBytes("{\"id\":\"../x\",\"want\":\"connect\"}".toByteArray()))
    }

    /** Sealed by a separate implementation of the same format; the Mac tests open the same bytes. */
    @Test fun opensTheSharedFixture() {
        val key = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(Base64.getDecoder().decode(FIXTURE_KEY)))

        assertEquals(answer, Nearby.open(Base64.getDecoder().decode(FIXTURE_ANSWER), key))
    }

    private companion object {
        // A throwaway key made only for this test.
        const val FIXTURE_KEY =
            "MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQCZx7RZNyPVF0cX6n9vlBG8mK45aFejL8J8C0le4/hTcYhCFQmI" +
            "8dbs0NfO54yKKmf8ctKEGPVxZm6QSDK1Fo5SceQb1IJ9oM/SYTQZl9z+y5co40tAcnKhEHc6Ea2Fi7IxsyM7d1/E4vUmkGZtFni5" +
            "SMc+qJ6iN6H/m09q8KlZbuXGg78LVQjf4LSAhGRXW41YXet4rKV7hDTsJrqavfGnuUlvwvP2sh33K0wYwg3JNDmaiy0hzT/RPG1o" +
            "G76HkolKJCsHknt/E/HHgwzRRMCm1Acb25KoW7OCbyrQr3Z3X4VByTUnhU0mUtO2Zs9cOn81sXPmKZm6ALLk+4hpKTebAgMBAAEC" +
            "ggEADpKcthmiFSb0D0GjGu1Cswca94i6SVYUzZF6PfpHhYzMN0rsEOSuE9oEoXBS4qL7ILK23VrKI5lr39NfrsZ47ToqvjJovUP4" +
            "fbzFZal9AU5EwFStxGk0EKxRSBj1wyKGW+xYaeG5mxxQ0/s6IZtQDGrnqrnq8n9oJCNRJtawja9tixbRNWU6XLt2pi94IMfXa7XE" +
            "2pHXzoSpO9SR/pkmo8EsMzK5W4KfVUvZwkS4lF0bHq7T0nXEuL3ifcYwMNKSpUqM+If4I4s3GNBNeFUCqcJcFfkYglarrzbQVhYI" +
            "d23syiCjKX5p8Nh+A+9+nB0Am2fxtyR8pQqmbf3BBwQZjQKBgQDMH/Rc6zrUFY40xMNYJDtmubGc5cHXRI7HwTwikSQnSCeahh1t" +
            "UqN5rV3DIY+xt7UAymbdzh3oONfRZWoyDOJgylu5MjNhaUP5Exys6Mq3VQaW0qARJ1mICa1mSea5DklMe7+2uysoyy4zufa8mVK3" +
            "6j/QPnwew1/TmduiH3fVfwKBgQDA3GZbS22Ak2x5B2jSpUQ149AK4DfaDPoYNmeFFviGrCoeW5AG813FXwDU6NUK7Bow7ZNRBpQG" +
            "rdLC+lwPEL2TqFC1eRTLf2zkZwM0/fQR5yS6vLmPFrwNglc7LxKAd67vS70kOjRIno/dp6raFCV5/UmmfuGx43glxlM9K2lD5QKB" +
            "gQCmO2OqhBpNexxrFs4qqp8BYjollupMH9XTESei0uZJYzZ1XcD7NbBRuADCl0NJLF0oPqyU93Vdl2USbu+TwPBeeI1H/XzgWHR1" +
            "k73nhlEICiMqkm6uaYg9A/yFb6uIivzgX2raKgTU3NpMX6ZzIr29bvP259v2xY71aLf3iH7ziwKBgQCbICxMfo0jgHEdoHIWDMyi" +
            "tA0g0lzaTNnVI918VY+tc0mlhWyByrrACLx4hJbn5CTk+hMmdy4VeTcvkYT+sS5rWFUiwrORQ3to89rGgwYQaGVItohiqZy1GQPl" +
            "HOW644mX/Mm0HAT17GQ3m6d3JgFG8A6PlzsehKKdb7qAVyyiaQKBgQCt771lXPJMSrb9fgv6Cj+SyjQdBEGEul/HTBtO26W+16KF" +
            "Bwa/hSKHzIWC+IJ7vDywaendNuO2WYpLK0Pk8cA900QESES6Xd09YPS5bL1kBn6XggpkkhqhfXJ0p1GXb4lVaf6mM/8q90/+YHi0" +
            "4kbKSDjptkQx4DEJC7n/tcCg2Q=="

        const val FIXTURE_ANSWER =
            "AQArbPlsvq+u5pCnKp3xbqn08vUTiyMKdHiHyc76dkfAf2YxNzrLsrKAAf1FZ8EtKMNvA/H7Qq7owg+AcWvGse9OFhR+iQGrCgFJ" +
            "MlOsz3LcjK8CNU4hneY/hqHcqyX+AknfOyUQiR2f520ed7r7sinSEffv39m10v5/WHnjzWLBT499Ri2PRThK2SMVUT5419DTMVTM" +
            "saOwREUDWTL3CwMq+FSBDcEN4x85UzK9hMBtMjtZepAZ6Czu4wk+AFTG3JYv6S5OpuIZDrlzggtxTLYm34Igf64vsuEDzAbvwS/V" +
            "TSDSL82P65Qk/seQ5s76QUdLL3ZN1rVQejK7fBaD7qa6h8RxWNBotWuq5mUsDL5SF1zffkGcJid4U/5MHinleHVEQ61HjVvS2JKf" +
            "S6eQ3sfIYwdYHtOCzdnwaDz1Nm/LFi+z6+Lpnt8S6OkqUs/eieaXfphAV8o+4eMw5xZ3jd8pjyw="
    }
}
