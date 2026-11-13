import XCTest
@testable import FlyyLinkKit

/// Mirrors RelayTest.kt and RelayTests.cs.
final class RelayTests: XCTestCase {
    private func wire(_ packet: NetworkPacket) throws -> NetworkPacket {
        try NetworkPacket.parse(try packet.serialize())
    }

    func testPhonePacketsRoundTrip() throws {
        let call = Call.event(.ringing, number: "+2348000000000", contactName: "Ada")
        let message = try XCTUnwrap(Relay.message(try wire(Relay.wrap(call, phoneId: "phone1", phoneName: "Pixel"))))

        XCTAssertEqual(message.phoneId, "phone1")
        XCTAssertEqual(message.phoneName, "Pixel")
        XCTAssertEqual(message.packet.type, PacketType.telephony)
        XCTAssertEqual(Call.state(message.packet), Call.state(call))
    }

    func testAnswersRoundTrip() throws {
        let reply = NotificationRequests.reply(to: "r1", message: "On my way")
        let message = try XCTUnwrap(Relay.message(try wire(Relay.wrap(reply, phoneId: "phone1", phoneName: "Pixel"))))

        XCTAssertEqual(message.packet.type, reply.type)
        XCTAssertEqual(message.packet.body, reply.body)
    }

    func testOnlyRelayablePacketsAreAccepted() throws {
        let ping = NetworkPacket(type: PacketType.ping)
        XCTAssertNil(Relay.message(try wire(Relay.wrap(ping, phoneId: "phone1", phoneName: "Pixel"))))
        XCTAssertNil(Relay.message(try wire(Relay.wrap(Call.event(.missed, number: "1"), phoneId: "", phoneName: "Pixel"))))
        XCTAssertNil(Relay.message(NetworkPacket(type: PacketType.relay, body: ["phoneId": "phone1"])))
        XCTAssertEqual(Relay.message(try wire(Relay.wrap(Call.event(.missed, number: "1"), phoneId: "p", phoneName: "")))?.phoneName, "Phone")
    }
}
