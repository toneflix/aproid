import XCTest
@testable import FlyyLinkKit

final class CallTests: XCTestCase {
    private func wire(_ packet: NetworkPacket) throws -> NetworkPacket {
        try NetworkPacket.parse(try packet.serialize())
    }

    func testEventsRoundTrip() throws {
        XCTAssertEqual(
            Call.state(try wire(Call.event(.ringing, number: "+2348012345678", contactName: "Ada", photo: "aGVsbG8="))),
            Call.State(event: .ringing, number: "+2348012345678", contactName: "Ada", photo: "aGVsbG8=")
        )
        XCTAssertEqual(Call.state(try wire(Call.ended(number: "555"))), Call.State(event: .ringing, number: "555", ended: true))
    }

    /// The same packet the Kotlin test reads.
    func testReadsKdeConnectMissedCall() throws {
        let packet = try NetworkPacket.parse(#"{"id":1,"type":"kdeconnect.telephony","body":{"event":"missedCall","phoneNumber":"555","contactName":"Bo"}}"#)

        XCTAssertEqual(Call.state(packet), Call.State(event: .missed, number: "555", contactName: "Bo"))
    }

    func testRequestsRoundTrip() throws {
        XCTAssertEqual(Call.request(try wire(Call.answer())), Call.Request(.answer))
        XCTAssertEqual(Call.request(try wire(Call.decline())), Call.Request(.decline))
        XCTAssertEqual(Call.request(try wire(Call.hangUp())), Call.Request(.hangUp))
        XCTAssertEqual(Call.request(try wire(Call.dial("+234801"))), Call.Request(.dial, number: "+234801"))
    }

    func testDialNeedsANumber() throws {
        XCTAssertNil(Call.request(try wire(Call.dial(" "))))
        XCTAssertNil(Call.state(try wire(Call.answer())))
    }
}
