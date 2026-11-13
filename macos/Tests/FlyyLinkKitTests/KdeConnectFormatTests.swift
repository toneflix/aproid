import XCTest
@testable import FlyyLinkKit

/// Packets in the shapes KDE Connect itself sends (protocol v8), so we keep working with its apps.
/// These are written from the protocol's documented field names. KdeConnectFormatTest.kt checks the same.
final class KdeConnectFormatTests: XCTestCase {
    private func parse(_ wire: String) throws -> NetworkPacket {
        try NetworkPacket.parse(Data(wire.utf8))
    }

    private func keys(_ packet: NetworkPacket) throws -> Set<String> {
        Set(try NetworkPacket.parse(try packet.serialize()).body.keys)
    }

    func testReadsKdeNotification() throws {
        // KDE sends the time as a string and an empty requestReplyId when there is no reply.
        let packet = try parse(#"{"id":1,"type":"kdeconnect.notification","body":{"id":"0|org.telegram|7|null|10234","appName":"Telegram","ticker":"Ann: hi","isClearable":true,"title":"Ann","text":"hi","time":"1700000000000","silent":"false","requestReplyId":"","actions":["Mark as read"]}}"#)

        let notification = try XCTUnwrap(PhoneNotification(packet: packet))

        XCTAssertEqual(notification.id, "0|org.telegram|7|null|10234")
        XCTAssertEqual(notification.time, 1_700_000_000_000)
        XCTAssertNil(notification.replyId)
        XCTAssertEqual(
            PhoneNotification.cancelledId(try parse(#"{"id":2,"type":"kdeconnect.notification","body":{"id":"0|org.telegram|7|null|10234","isCancel":true}}"#)),
            "0|org.telegram|7|null|10234"
        )
    }

    func testWritesKdeNotificationFields() throws {
        let sent = try keys(PhoneNotification(id: "k", appName: "Signal", title: "Bo", text: "hi", time: 1, replyId: "r1").toPacket())

        XCTAssertTrue(sent.isSuperset(of: ["id", "appName", "title", "text", "ticker", "time", "isClearable", "requestReplyId"]))
        XCTAssertEqual(try keys(NotificationRequests.reply(to: "r1", message: "ok")), ["requestReplyId", "message"])
        XCTAssertEqual(try keys(NotificationRequests.dismiss("k")), ["cancel"])
        XCTAssertEqual(try keys(NotificationRequests.requestAll()), ["request"])
    }

    func testReadsKdeShares() throws {
        let file = try parse(#"{"id":1,"type":"kdeconnect.share.request","body":{"filename":"IMG_1.jpg","lastModified":1700000000000,"numberOfFiles":1,"totalPayloadSize":2048},"payloadSize":2048,"payloadTransferInfo":{"port":1739}}"#)

        XCTAssertEqual(Share(packet: file), .file(name: "IMG_1.jpg", size: 2048))
        XCTAssertEqual(file.payloadPort, 1739)
        XCTAssertEqual(Share(packet: try parse(#"{"id":1,"type":"kdeconnect.share.request","body":{"url":"https://kde.org"}}"#)), .link("https://kde.org"))
        XCTAssertEqual(Share(packet: try parse(#"{"id":1,"type":"kdeconnect.share.request","body":{"text":"hello"}}"#)), .text("hello"))
    }

    func testReadsKdeTelephony() throws {
        let ringing = try XCTUnwrap(Call.state(try parse(#"{"id":1,"type":"kdeconnect.telephony","body":{"event":"ringing","phoneNumber":"+2348000000000","contactName":"Ann","phoneThumbnail":"aGk="}}"#)))
        let ended = try XCTUnwrap(Call.state(try parse(#"{"id":2,"type":"kdeconnect.telephony","body":{"event":"ringing","phoneNumber":"+2348000000000","isCancel":true}}"#)))

        XCTAssertEqual(ringing.event, .ringing)
        XCTAssertEqual(ringing.contactName, "Ann")
        XCTAssertTrue(ended.ended)
        XCTAssertEqual(try keys(Call.event(.talking, number: "1", contactName: "Bo")), ["event", "phoneNumber", "contactName"])
    }

    func testReadsKdeSms() throws {
        let packet = try parse(#"{"id":1,"type":"kdeconnect.sms.messages","body":{"version":2,"messages":[{"_id":"41","thread_id":"7","body":"hi","addresses":[{"address":"+2348000000000"}],"date":"1700000000000","type":"1","read":"0","event":1,"sub_id":1}]}}"#)

        let message = try XCTUnwrap(Sms.messages(packet)?.first)

        XCTAssertEqual(message.id, 41)
        XCTAssertEqual(message.threadId, 7)
        XCTAssertTrue(message.isIncoming)
        XCTAssertFalse(message.isRead)

        // KDE's desktop sends version 2 with an address list; older apps sent one phoneNumber.
        let v2 = try XCTUnwrap(Sms.sendRequest(try parse(#"{"id":1,"type":"kdeconnect.sms.request","body":{"version":2,"addresses":[{"address":"555"}],"messageBody":"yo","subID":-1}}"#)))
        let v1 = try XCTUnwrap(Sms.sendRequest(try parse(#"{"id":1,"type":"kdeconnect.sms.request","body":{"sendSms":true,"phoneNumber":"555","messageBody":"yo"}}"#)))
        XCTAssertEqual(v2.addresses, ["555"])
        XCTAssertEqual(v1.addresses, ["555"])

        let asked = try XCTUnwrap(Sms.conversationRequest(try parse(#"{"id":1,"type":"kdeconnect.sms.request_conversation","body":{"threadID":7,"rangeStartTimestamp":1700000000000,"numberToRequest":20}}"#)))
        XCTAssertEqual(asked.threadId, 7)
    }

    func testReadsKdeMedia() throws {
        let player = try XCTUnwrap(MediaPlayer(packet: try parse(#"{"id":1,"type":"kdeconnect.mpris","body":{"player":"Spotify","title":"Song","artist":"Band","album":"LP","isPlaying":true,"pos":1000,"length":200000,"volume":70,"canPlay":true,"canPause":true,"canGoNext":true,"canGoPrevious":true,"canSeek":true}}"#)))
        let request = try XCTUnwrap(MediaRequest(packet: try parse(#"{"id":1,"type":"kdeconnect.mpris.request","body":{"player":"Spotify","action":"PlayPause"}}"#)))

        XCTAssertEqual(player.title, "Song")
        XCTAssertEqual(player.length, 200_000)
        XCTAssertEqual(request.action, .playPause)
        XCTAssertTrue(try keys(MediaRequest.seek("Spotify", to: 5000).toPacket()).contains("SetPosition"))
    }

    func testReadsKdeClipboardBatteryAndPairing() throws {
        XCTAssertEqual(Clipboard.content(try parse(#"{"id":1,"type":"kdeconnect.clipboard","body":{"content":"copied"}}"#)), "copied")
        XCTAssertEqual(Clipboard.content(try parse(#"{"id":1,"type":"kdeconnect.clipboard.connect","body":{"content":"copied","timestamp":1700000000000}}"#)), "copied")
        XCTAssertEqual(BatteryStatus(packet: try parse(#"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":9,"isCharging":false,"thresholdEvent":1}}"#)), BatteryStatus(charge: 9, isCharging: false, isLow: true))

        guard case .send(let request) = PairingStateMachine().requestPair(now: 1_700_000_000) else {
            return XCTFail("no pair request")
        }
        XCTAssertEqual(try keys(request), ["pair", "timestamp"])

        // KDE Connect v8 pairs with a timestamp in seconds.
        let peer = PairingStateMachine()
        _ = peer.handle(try parse(#"{"id":1,"type":"kdeconnect.pair","body":{"pair":true,"timestamp":1700000000}}"#), now: 1_700_000_010)
        XCTAssertEqual(peer.state, .requestedByPeer)
    }

    func testOurOwnPacketsAreNamespacedAndAdvertised() {
        XCTAssertTrue(Capabilities.mvp.allSatisfy { $0.hasPrefix("kdeconnect.") || $0.hasPrefix("flyylink.") })
        XCTAssertTrue(Capabilities.mvp.isSuperset(of: [
            PacketType.photos, PacketType.photosRequest, PacketType.photosDownload, PacketType.photosFile,
            PacketType.screen, PacketType.screenRequest, PacketType.screenInput,
            PacketType.location, PacketType.locationRequest, PacketType.shareResume,
            PacketType.clipboardFile, PacketType.callRequest, PacketType.heartbeat,
        ]))
    }
}
