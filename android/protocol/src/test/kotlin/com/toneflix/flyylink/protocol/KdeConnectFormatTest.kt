package com.toneflix.flyylink.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Packets in the shapes KDE Connect itself sends (protocol v8), so we keep working with its apps.
 * These are written from the protocol's documented field names. KdeConnectFormatTests.swift checks the same.
 */
class KdeConnectFormatTest {
    private fun parse(wire: String) = NetworkPacket.parse(wire)

    private fun keys(packet: NetworkPacket) = NetworkPacket.parse(packet.serialize()).body.keys

    @Test fun readsKdeNotification() {
        // KDE sends the time as a string and an empty requestReplyId when there is no reply.
        val packet = parse("""{"id":1,"type":"kdeconnect.notification","body":{"id":"0|org.telegram|7|null|10234","appName":"Telegram","ticker":"Ann: hi","isClearable":true,"title":"Ann","text":"hi","time":"1700000000000","silent":"false","requestReplyId":"","actions":["Mark as read"]}}""")

        val notification = PhoneNotification.fromPacket(packet)!!

        assertEquals("0|org.telegram|7|null|10234", notification.id)
        assertEquals(1_700_000_000_000, notification.time)
        assertEquals(null, notification.replyId)
        assertEquals("0|org.telegram|7|null|10234", PhoneNotification.cancelledId(parse("""{"id":2,"type":"kdeconnect.notification","body":{"id":"0|org.telegram|7|null|10234","isCancel":true}}""")))
    }

    @Test fun writesKdeNotificationFields() {
        val sent = keys(PhoneNotification("k", "Signal", "Bo", "hi", 1, replyId = "r1").toPacket())

        assertTrue(sent.containsAll(listOf("id", "appName", "title", "text", "ticker", "time", "isClearable", "requestReplyId")))
        assertEquals(setOf("requestReplyId", "message"), keys(NotificationRequests.reply("r1", "ok")))
        assertEquals(setOf("cancel"), keys(NotificationRequests.dismiss("k")))
        assertEquals(setOf("request"), keys(NotificationRequests.requestAll()))
    }

    @Test fun readsKdeShares() {
        val file = parse("""{"id":1,"type":"kdeconnect.share.request","body":{"filename":"IMG_1.jpg","lastModified":1700000000000,"numberOfFiles":1,"totalPayloadSize":2048},"payloadSize":2048,"payloadTransferInfo":{"port":1739}}""")

        assertEquals(Share.File("IMG_1.jpg", 2048), Share.fromPacket(file))
        assertEquals(1739, file.payloadPort)
        assertEquals(Share.Link("https://kde.org"), Share.fromPacket(parse("""{"id":1,"type":"kdeconnect.share.request","body":{"url":"https://kde.org"}}""")))
        assertEquals(Share.Text("hello"), Share.fromPacket(parse("""{"id":1,"type":"kdeconnect.share.request","body":{"text":"hello"}}""")))
    }

    @Test fun readsKdeTelephony() {
        val ringing = Call.state(parse("""{"id":1,"type":"kdeconnect.telephony","body":{"event":"ringing","phoneNumber":"+2348000000000","contactName":"Ann","phoneThumbnail":"aGk="}}"""))!!
        val ended = Call.state(parse("""{"id":2,"type":"kdeconnect.telephony","body":{"event":"ringing","phoneNumber":"+2348000000000","isCancel":true}}"""))!!

        assertEquals(CallEvent.RINGING, ringing.event)
        assertEquals("Ann", ringing.contactName)
        assertTrue(ended.ended)
        assertEquals(setOf("event", "phoneNumber", "contactName"), keys(Call.event(CallEvent.TALKING, "1", "Bo")))
    }

    @Test fun readsKdeSms() {
        val packet = parse("""{"id":1,"type":"kdeconnect.sms.messages","body":{"version":2,"messages":[{"_id":"41","thread_id":"7","body":"hi","addresses":[{"address":"+2348000000000"}],"date":"1700000000000","type":"1","read":"0","event":1,"sub_id":1}]}}""")

        val message = Sms.messages(packet)!!.single()

        assertEquals(41L, message.id)
        assertEquals(7L, message.threadId)
        assertTrue(message.isIncoming)
        assertEquals(false, message.isRead)

        // KDE's desktop sends version 2 with an address list; older apps sent one phoneNumber.
        val v2 = Sms.sendRequest(parse("""{"id":1,"type":"kdeconnect.sms.request","body":{"version":2,"addresses":[{"address":"555"}],"messageBody":"yo","subID":-1}}"""))!!
        val v1 = Sms.sendRequest(parse("""{"id":1,"type":"kdeconnect.sms.request","body":{"sendSms":true,"phoneNumber":"555","messageBody":"yo"}}"""))!!
        assertEquals(listOf("555"), v2.addresses)
        assertEquals(listOf("555"), v1.addresses)

        val asked = Sms.conversationRequest(parse("""{"id":1,"type":"kdeconnect.sms.request_conversation","body":{"threadID":7,"rangeStartTimestamp":1700000000000,"numberToRequest":20}}"""))!!
        assertEquals(7L, asked.threadId)
    }

    @Test fun readsKdeMedia() {
        val player = MediaPlayer.fromPacket(parse("""{"id":1,"type":"kdeconnect.mpris","body":{"player":"Spotify","title":"Song","artist":"Band","album":"LP","isPlaying":true,"pos":1000,"length":200000,"volume":70,"canPlay":true,"canPause":true,"canGoNext":true,"canGoPrevious":true,"canSeek":true}}"""))!!
        val request = MediaRequest.fromPacket(parse("""{"id":1,"type":"kdeconnect.mpris.request","body":{"player":"Spotify","action":"PlayPause"}}"""))!!

        assertEquals("Song", player.title)
        assertEquals(200_000L, player.length)
        assertEquals(MediaAction.PLAY_PAUSE, request.action)
        assertTrue(keys(MediaRequest.seek("Spotify", 5000).toPacket()).contains("SetPosition"))
    }

    @Test fun readsKdeClipboardBatteryAndPairing() {
        assertEquals("copied", Clipboard.content(parse("""{"id":1,"type":"kdeconnect.clipboard","body":{"content":"copied"}}""")))
        assertEquals("copied", Clipboard.content(parse("""{"id":1,"type":"kdeconnect.clipboard.connect","body":{"content":"copied","timestamp":1700000000000}}""")))
        assertEquals(BatteryStatus(9, false, isLow = true), BatteryStatus.fromPacket(parse("""{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":9,"isCharging":false,"thresholdEvent":1}}""")))

        val request = PairingStateMachine().requestPair(1_700_000_000) as PairAction.Send
        assertEquals(setOf("pair", "timestamp"), keys(request.packet))

        // KDE Connect v8 pairs with a timestamp in seconds.
        val peer = PairingStateMachine()
        peer.onPacket(parse("""{"id":1,"type":"kdeconnect.pair","body":{"pair":true,"timestamp":1700000000}}"""), 1_700_000_010)
        assertEquals(PairState.REQUESTED_BY_PEER, peer.state)
    }

    @Test fun ourOwnPacketsAreNamespacedAndAdvertised() {
        val ours = PacketType::class.java.declaredFields
            .filter { it.type == String::class.java }
            .map { it.get(null) as String }
            .filter { it.startsWith("flyylink.") }

        assertTrue(ours.isNotEmpty())
        assertTrue(ours.all { it in Capabilities.mvp })
        assertTrue(Capabilities.mvp.all { it.startsWith("kdeconnect.") || it.startsWith("flyylink.") })
    }
}
