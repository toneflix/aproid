package com.toneflix.aproid.protocol

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.net.InetAddress
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class LanLinkTest {
    private class Peer(name: String, type: DeviceType, ports: IntRange) {
        val identity = DeviceIdentity(DeviceIdentity.newDeviceId(), name, type)
        val certificate = DeviceCertificate.generate(identity.deviceId)
        val trust = InMemoryTrustStore()
        val links = LinkedBlockingQueue<DeviceLink>()

        // High ports so the test does not clash with a real KDE Connect install.
        val lan = LanLink({ identity }, certificate, trust, { links.put(it) }, udpPort = 41716, tcpPorts = ports)

        fun nextLink(): DeviceLink = links.poll(10, TimeUnit.SECONDS) ?: error("no link")
    }

    private lateinit var mac: Peer
    private lateinit var phone: Peer

    @Before fun setUp() {
        mac = Peer("Mac", DeviceType.LAPTOP, 41716..41730)
        phone = Peer("Phone", DeviceType.PHONE, 41731..41764)
        mac.lan.start()
    }

    @After fun tearDown() {
        mac.lan.stop()
    }

    private fun connect(): Pair<DeviceLink, DeviceLink> {
        phone.lan.connect(mac.identity.copy(tcpPort = mac.lan.tcpPort), InetAddress.getLoopbackAddress())

        return phone.nextLink() to mac.nextLink()
    }

    @Test fun linkIsEncryptedAndCarriesIdentities() {
        val (onPhone, onMac) = connect()

        assertEquals(mac.identity.deviceId, onPhone.identity.deviceId)
        assertEquals(phone.identity.deviceId, onMac.identity.deviceId)
        assertEquals(mac.identity.deviceId, DeviceCertificate.commonName(onPhone.certificate))
    }

    @Test fun pairingShowsTheSameCodeAndTrustsBothSides() {
        val (onPhone, onMac) = connect()
        val requests = LinkedBlockingQueue<String>()
        val pings = LinkedBlockingQueue<NetworkPacket>()
        val paired = LinkedBlockingQueue<PairState>()

        val phoneDevice = Device(onPhone, phone.certificate, phone.trust).apply {
            listener = object : Device.Listener {
                override fun onPairStateChanged(device: Device, state: PairState) {
                    if (state == PairState.PAIRED) paired.put(state)
                }
            }
            start()
        }
        val macDevice = Device(onMac, mac.certificate, mac.trust).apply {
            listener = object : Device.Listener {
                override fun onPairRequest(device: Device, code: String) = requests.put(code)

                override fun onPacket(device: Device, packet: NetworkPacket) = pings.put(packet)
            }
            start()
        }

        phoneDevice.requestPair()
        val codeOnMac = requests.poll(10, TimeUnit.SECONDS)

        assertEquals(phoneDevice.verificationCode, codeOnMac)

        macDevice.accept()

        assertEquals(PairState.PAIRED, paired.poll(10, TimeUnit.SECONDS))
        assertTrue(phone.trust.isTrusted(mac.identity.deviceId))
        assertTrue(mac.trust.isTrusted(phone.identity.deviceId))

        assertTrue(phoneDevice.send(NetworkPacket(PacketType.PING)))
        assertEquals(PacketType.PING, pings.poll(10, TimeUnit.SECONDS)?.type)
    }

    @Test fun unpairedDevicesCannotSend() {
        val (onPhone, onMac) = connect()
        val phoneDevice = Device(onPhone, phone.certificate, phone.trust)
        Device(onMac, mac.certificate, mac.trust).start()

        assertFalse(phoneDevice.send(NetworkPacket(PacketType.PING)))
    }

    @Test fun changedCertificateIsRejected() {
        mac.trust.trust(phone.identity.deviceId, DeviceCertificate.generate(phone.identity.deviceId).encodedCertificate)

        runCatching { phone.lan.connect(mac.identity.copy(tcpPort = mac.lan.tcpPort), InetAddress.getLoopbackAddress()) }

        assertEquals(null, mac.links.poll(3, TimeUnit.SECONDS))
    }
}
