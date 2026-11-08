package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PhoneNotificationTest {
    private val sample = PhoneNotification(
        id = "0|com.whatsapp|1|null|10123",
        appName = "WhatsApp",
        title = "Ada",
        text = "Are you coming?",
        time = 1_700_000_000_000,
        replyId = "f3b2c1",
        iconHash = "900150983cd24fb0d6963f7d28e17f72",
    )

    @Test fun roundTrips() {
        val back = PhoneNotification.fromPacket(NetworkPacket.parse(sample.toPacket().serialize()))

        assertEquals(sample, back)
    }

    @Test fun readsKdeConnectPacket() {
        val wire = """{"id":1,"type":"kdeconnect.notification","body":{"id":"k1","appName":"Signal","title":"Bo","text":"hi","time":"1700000000000","isClearable":true,"requestReplyId":""}}"""

        val note = PhoneNotification.fromPacket(NetworkPacket.parse(wire))

        assertEquals("Signal", note?.appName)
        assertEquals(1_700_000_000_000, note?.time)
        assertNull(note?.replyId)
    }

    @Test fun iconHashIsMd5Hex() {
        assertEquals("900150983cd24fb0d6963f7d28e17f72", PhoneNotification.iconHash("abc".toByteArray()))
    }

    @Test fun cancelIsNotANotification() {
        val cancel = PhoneNotification.cancelPacket("k1")

        assertNull(PhoneNotification.fromPacket(cancel))
        assertEquals("k1", PhoneNotification.cancelledId(cancel))
        assertNull(PhoneNotification.cancelledId(sample.toPacket()))
    }

    @Test fun requestsCarryTheRightFields() {
        assertEquals(true, NotificationRequests.requestAll().bool("request"))
        assertEquals("k1", NotificationRequests.dismiss("k1").string("cancel"))

        val reply = NotificationRequests.reply("f3b2c1", "On my way")

        assertEquals(PacketType.NOTIFICATION_REPLY, reply.type)
        assertEquals("f3b2c1", reply.string("requestReplyId"))
        assertEquals("On my way", reply.string("message"))
    }
}
