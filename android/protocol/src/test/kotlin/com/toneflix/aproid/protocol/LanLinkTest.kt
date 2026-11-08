package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Test
import java.net.InetAddress
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class LanLinkTest {
    @Test fun identitiesAreExchangedOverTcp() {
        val mac = DeviceIdentity(DeviceIdentity.newDeviceId(), "Mac", DeviceType.LAPTOP)
        val phone = DeviceIdentity(DeviceIdentity.newDeviceId(), "Phone", DeviceType.PHONE)
        val seenByMac = LinkedBlockingQueue<DiscoveredPeer>()
        val seenByPhone = LinkedBlockingQueue<DiscoveredPeer>()

        // High ports so the test does not clash with a real KDE Connect install.
        val macLink = LanLink({ mac }, { p, _ -> seenByMac.put(p) }, udpPort = 41716, tcpPorts = 41716..41764)
        val phoneLink = LanLink({ phone }, { p, _ -> seenByPhone.put(p) }, udpPort = 41716, tcpPorts = 41716..41764)
        macLink.start()
        try {
            val announced = mac.copy(tcpPort = macLink.tcpPort)
            phoneLink.connect(announced, InetAddress.getLoopbackAddress())
            assertEquals(mac.deviceId, seenByPhone.poll(5, TimeUnit.SECONDS)?.identity?.deviceId)
            assertEquals(phone.deviceId, seenByMac.poll(5, TimeUnit.SECONDS)?.identity?.deviceId)
        } finally {
            macLink.stop()
        }
    }
}
