package com.toneflix.aproid.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FlyyDropTest {
    private var now = 1_000_000L
    private val sender = FlyyDrop { now }
    private val receiver = FlyyDrop { now }.apply { receiving = FlyyDrop.Receiving.EVERYONE }
    private val photo = FlyyDrop.Item("photo.jpg", 2048)
    private val notes = FlyyDrop.Item("notes.txt", 10)

    private fun wire(packet: NetworkPacket) = NetworkPacket.parse(packet.serialize())

    /** The sender asks the receiver, as it would over the network, and returns the receiver's view. */
    private fun ask(items: List<FlyyDrop.Item> = listOf(photo, notes), text: String? = null): FlyyDrop.Offer {
        val request = sender.request("receiver", items, text)
        assertTrue(sender.admitsOutgoing("receiver", request))
        assertTrue(receiver.admitsIncoming("sender", wire(request)))

        val incoming = receiver.onRequest("sender", wire(request), isPaired = false)
        return (incoming as FlyyDrop.Incoming.Ask).offer
    }

    private fun accept(offer: FlyyDrop.Offer) {
        val response = receiver.accept(offer.id)!!
        assertTrue(receiver.admitsOutgoing("sender", response))
        assertTrue(sender.admitsIncoming("receiver", wire(response)))
        assertTrue(sender.onResponse("receiver", wire(response))!!.accepted)
    }

    /** A file as it arrives: the sender's packet with the payload size added. */
    private fun arriving(id: String, item: FlyyDrop.Item, size: Long = item.size) =
        wire(FlyyDrop.file(id, item).copy(payloadSize = size))

    @Test fun requestRoundTrips() {
        val offer = ask(text = null)

        assertEquals(listOf(photo, notes), offer.items)
        assertEquals(2058, offer.totalSize)
        assertEquals("sender", offer.deviceId)
    }

    @Test fun acceptedFilesComeInOnceEach() {
        val offer = ask()
        accept(offer)

        assertTrue(sender.admitsOutgoing("receiver", FlyyDrop.file(offer.id, photo)))
        assertTrue(receiver.admitsIncoming("sender", arriving(offer.id, photo)))
        assertFalse(receiver.admitsIncoming("sender", arriving(offer.id, photo)))
        assertTrue(receiver.admitsIncoming("sender", arriving(offer.id, notes)))
        assertFalse(receiver.isActive(offer.id))
    }

    @Test fun nothingComesInBeforeAccepting() {
        val offer = ask()

        assertFalse(receiver.admitsIncoming("sender", arriving(offer.id, photo)))
        assertFalse(sender.admitsOutgoing("receiver", FlyyDrop.file(offer.id, photo)))
    }

    @Test fun onlyTheDeclaredFilesAndSizesComeIn() {
        val offer = ask()
        accept(offer)

        assertFalse(receiver.admitsIncoming("sender", arriving(offer.id, FlyyDrop.Item("other.exe", 2048))))
        assertFalse(receiver.admitsIncoming("sender", arriving(offer.id, photo, size = 1_000_000)))
        assertFalse(receiver.admitsIncoming("someone-else", arriving(offer.id, photo)))
        assertFalse(receiver.admitsIncoming("sender", wire(Share.file(photo.name, photo.size).copy(payloadSize = photo.size))))
    }

    @Test fun guestsGetNoOtherPackets() {
        ask()

        assertFalse(receiver.admitsIncoming("sender", Clipboard.packet("hi")))
        assertFalse(receiver.admitsIncoming("sender", FindMyPhone.request()))
        assertFalse(receiver.admitsIncoming("sender", Share.text("hi")))
        assertFalse(receiver.admitsOutgoing("sender", NotificationRequests.reply("r1", "hi")))
    }

    @Test fun acceptedLinkComesInOnce() {
        val offer = ask(items = emptyList(), text = "https://toneflix.net")
        accept(offer)

        val link = FlyyDrop.text(offer.id, "https://toneflix.net")
        assertEquals(Share.Link("https://toneflix.net"), Share.fromPacket(link))
        assertTrue(receiver.admitsIncoming("sender", wire(link)))
        assertFalse(receiver.admitsIncoming("sender", wire(link)))
        assertEquals(Share.Text("hello there"), Share.fromPacket(FlyyDrop.text("x", "hello there")))
    }

    @Test fun declineEndsTheRequestOnBothSides() {
        val offer = ask()
        val response = receiver.decline(offer.id)!!

        assertTrue(receiver.admitsOutgoing("sender", response))
        val answer = sender.onResponse("receiver", wire(response))!!
        assertFalse(answer.accepted)
        assertEquals(FlyyDrop.Reason.DECLINED, answer.reason)
        assertFalse(sender.isActive(offer.id))
        assertFalse(receiver.isActive(offer.id))
    }

    @Test fun offDeclinesStrangersButAsksPairedDevices() {
        receiver.receiving = FlyyDrop.Receiving.OFF
        val request = wire(sender.request("receiver", listOf(photo)))

        val reply = receiver.onRequest("sender", request, isPaired = false) as FlyyDrop.Incoming.Reply
        assertEquals(FlyyDrop.Reason.UNAVAILABLE, sender.onResponse("receiver", wire(reply.packet))?.reason)

        val again = wire(sender.request("receiver", listOf(photo)))
        assertTrue(receiver.onRequest("sender", again, isPaired = true) is FlyyDrop.Incoming.Ask)
    }

    @Test fun everyoneForTenMinutesRunsOut() {
        receiver.receiving = FlyyDrop.Receiving.EVERYONE_FOR_10_MINUTES
        assertEquals(now + FlyyDrop.EVERYONE_MS, receiver.receivingUntil)

        now += FlyyDrop.EVERYONE_MS
        assertEquals(FlyyDrop.Receiving.OFF, receiver.receiving)
        assertNull(receiver.receivingUntil)
    }

    @Test fun oneRequestAtATimePerDevice() {
        ask()
        val second = wire(sender.request("receiver", listOf(notes)))

        val reply = receiver.onRequest("sender", second, isPaired = false) as FlyyDrop.Incoming.Reply
        assertEquals(FlyyDrop.Reason.BUSY, FlyyDrop.Reason.fromWire(reply.packet.string("reason")))
    }

    @Test fun unansweredRequestsExpire() {
        val offer = ask()

        now += FlyyDrop.ASK_MS
        assertEquals(listOf(offer.id), receiver.expire().map { it.id })
        assertNull(receiver.accept(offer.id))
    }

    @Test fun cancelReachesTheOtherSide() {
        val offer = ask()
        val cancel = sender.cancel(offer.id)!!

        assertTrue(sender.admitsOutgoing("receiver", cancel))
        assertNull(receiver.onCancel("intruder", wire(cancel)))
        assertEquals(offer.id, receiver.onCancel("sender", wire(cancel))?.id)
        assertFalse(receiver.isActive(offer.id))
    }

    @Test fun responsesOnlyCountFromTheAskedDevice() {
        val request = sender.request("receiver", listOf(photo))
        val id = request.string("id")!!
        val forged = NetworkPacket(PacketType.FLYYDROP_RESPONSE, NetworkPacket.body("id" to id, "accept" to true))

        assertFalse(sender.admitsIncoming("intruder", forged))
        assertNull(sender.onResponse("intruder", forged))
        assertNotNull(sender.onResponse("receiver", forged))
    }

    @Test fun malformedRequestsAreIgnored() {
        assertNull(FlyyDrop.offer("d", NetworkPacket(PacketType.FLYYDROP_REQUEST, NetworkPacket.body("id" to "x"))))
        assertNull(FlyyDrop.offer("d", NetworkPacket(PacketType.FLYYDROP_REQUEST, NetworkPacket.body("text" to "hi"))))

        val negative = NetworkPacket.parse("""{"id":1,"type":"flyylink.flyydrop.request","body":{"id":"x","files":[{"name":"a","size":-1}]}}""")
        assertNull(FlyyDrop.offer("d", negative))
        assertEquals("passwd", FlyyDrop.Item("../../etc/passwd", 1).safeName)
    }
}
