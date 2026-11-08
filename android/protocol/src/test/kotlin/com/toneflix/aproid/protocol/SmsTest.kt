package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SmsTest {
    private val message = SmsMessage(
        id = 41,
        threadId = 7,
        body = "Running late, 10 min",
        addresses = listOf(SmsAddress("+2348012345678", "Ada")),
        date = 1_700_000_000_000,
        isIncoming = true,
        isRead = false,
        subscriptionId = 1,
        attachments = listOf(SmsAttachment(3, "image/jpeg", "part-3", "aGVsbG8=")),
    )

    private fun wire(packet: NetworkPacket) = NetworkPacket.parse(packet.serialize())

    @Test fun messagesRoundTrip() {
        val sent = message.copy(id = 42, body = "No worries", isIncoming = false, isRead = true, attachments = emptyList())

        assertEquals(listOf(message, sent), Sms.messages(wire(Sms.messagesPacket(listOf(message, sent)))))
    }

    @Test fun readsKdeConnectMessage() {
        val packet = NetworkPacket.parse(
            """{"id":1,"type":"kdeconnect.sms.messages","body":{"version":2,"messages":[{"_id":"5","thread_id":2,"body":"hi","date":1700000000000,"type":2,"read":1,"event":1,"addresses":[{"address":"555"}]}]}}""",
        )

        val read = Sms.messages(packet)!!.single()

        assertEquals(5L, read.id)
        assertEquals(false, read.isIncoming)
        assertEquals(listOf(SmsAddress("555")), read.addresses)
    }

    @Test fun requestsRoundTrip() {
        assertEquals(Sms.ConversationRequest(7, 1_700_000_000_000, 30), Sms.conversationRequest(wire(Sms.requestConversation(7, 1_700_000_000_000, 30))))
        assertEquals(Sms.ConversationRequest(7, null, 50), Sms.conversationRequest(wire(Sms.requestConversation(7))))
        assertEquals(Sms.SendRequest(listOf("+234801", "+234802"), "On my way", 2), Sms.sendRequest(wire(Sms.send(listOf("+234801", "+234802"), "On my way", 2))))
        assertEquals(PacketType.SMS_REQUEST_CONVERSATIONS, Sms.requestConversations().type)
    }

    @Test fun readsVersionOneSendRequest() {
        val packet = NetworkPacket.parse("""{"id":1,"type":"kdeconnect.sms.request","body":{"phoneNumber":"555","messageBody":"yo"}}""")

        assertEquals(Sms.SendRequest(listOf("555"), "yo", null), Sms.sendRequest(packet))
        assertNull(Sms.messages(packet))
    }
}
