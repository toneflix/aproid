import XCTest
@testable import AproidKit

final class PhoneNotificationTests: XCTestCase {
    private let sample = PhoneNotification(
        id: "0|com.whatsapp|1|null|10123",
        appName: "WhatsApp",
        title: "Ada",
        text: "Are you coming?",
        time: 1_700_000_000_000,
        replyId: "f3b2c1",
        iconHash: "900150983cd24fb0d6963f7d28e17f72",
        actions: ["Mark as read", "Archive"]
    )

    func testRoundTrips() throws {
        let back = PhoneNotification(packet: try NetworkPacket.parse(try sample.toPacket().serialize()))

        XCTAssertEqual(back, sample)
    }

    /// The same packet the Kotlin test reads.
    func testReadsKdeConnectPacket() throws {
        let wire = #"{"id":1,"type":"kdeconnect.notification","body":{"id":"k1","appName":"Signal","title":"Bo","text":"hi","time":"1700000000000","isClearable":true,"requestReplyId":""}}"#

        let note = PhoneNotification(packet: try NetworkPacket.parse(wire))

        XCTAssertEqual(note?.appName, "Signal")
        XCTAssertEqual(note?.time, 1_700_000_000_000)
        XCTAssertNil(note?.replyId)
    }

    func testIconHashIsMd5Hex() {
        XCTAssertEqual(PhoneNotification.iconHash(Array("abc".utf8)), "900150983cd24fb0d6963f7d28e17f72")
    }

    func testCancelIsNotANotification() {
        let cancel = PhoneNotification.cancelPacket(id: "k1")

        XCTAssertNil(PhoneNotification(packet: cancel))
        XCTAssertEqual(PhoneNotification.cancelledId(cancel), "k1")
        XCTAssertNil(PhoneNotification.cancelledId(sample.toPacket()))
    }

    func testRequestsCarryTheRightFields() {
        XCTAssertEqual(NotificationRequests.requestAll().bool("request"), true)
        XCTAssertEqual(NotificationRequests.dismiss("k1").string("cancel"), "k1")

        let reply = NotificationRequests.reply(to: "f3b2c1", message: "On my way")

        XCTAssertEqual(reply.type, PacketType.notificationReply)
        XCTAssertEqual(reply.string("requestReplyId"), "f3b2c1")
        XCTAssertEqual(reply.string("message"), "On my way")
    }

    func testActionRoundTripsAndNeedsBothFields() throws {
        let pressed = NotificationAction(packet: try NetworkPacket.parse(try NotificationRequests.action(id: "k1", action: "Archive").serialize()))

        XCTAssertEqual(pressed, NotificationAction(id: "k1", action: "Archive"))
        XCTAssertNil(NotificationAction(packet: NetworkPacket(type: PacketType.notificationAction, body: ["key": .string("k1")])))
    }

    /// The same packet the Kotlin test reads.
    func testReadsKdeConnectActions() throws {
        let wire = #"{"id":1,"type":"kdeconnect.notification","body":{"id":"k1","appName":"Gmail","title":"Bo","text":"hi","actions":["Archive","Reply"]}}"#

        XCTAssertEqual(PhoneNotification(packet: try NetworkPacket.parse(wire))?.actions, ["Archive", "Reply"])
    }
}
