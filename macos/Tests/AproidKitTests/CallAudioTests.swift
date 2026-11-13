import XCTest
@testable import AproidKit

final class CallAudioTests: XCTestCase {
    private func wire(_ packet: NetworkPacket) throws -> NetworkPacket {
        try NetworkPacket.parse(try packet.serialize())
    }

    func testRequestsRoundTrip() throws {
        let pair = CallAudio.Request(.pair, address: "A4:83:E7:01:02:0F", name: "Obi's MacBook")

        XCTAssertEqual(CallAudio.request(try wire(CallAudio.request(pair))), pair)
        XCTAssertEqual(
            CallAudio.request(try wire(CallAudio.request(CallAudio.Request(.status, address: "a4-83-e7-01-02-0f")))),
            CallAudio.Request(.status, address: "A4:83:E7:01:02:0F")
        )
    }

    func testStatusRoundTrips() throws {
        let status = CallAudio.Status(bluetoothOn: true, allowed: true, paired: true, connected: false, name: "TECNO SPARK")

        XCTAssertEqual(CallAudio.status(try wire(CallAudio.status(status))), status)
    }

    /// The same packet the Kotlin test reads.
    func testReadsSharedStatus() throws {
        let packet = try NetworkPacket.parse(#"{"id":1,"type":"flyylink.callaudio","body":{"bluetoothOn":true,"allowed":false,"paired":false,"connected":false}}"#)

        XCTAssertEqual(CallAudio.status(packet), CallAudio.Status(bluetoothOn: true, allowed: false, paired: false, connected: false))
    }

    func testNormalizesAddresses() {
        XCTAssertEqual(CallAudio.normalizeAddress("a4-83-e7-01-02-0f"), "A4:83:E7:01:02:0F")
        XCTAssertEqual(CallAudio.normalizeAddress("a483e701020f"), "A4:83:E7:01:02:0F")
        XCTAssertNil(CallAudio.normalizeAddress("a4-83-e7-01-02"))
        XCTAssertNil(CallAudio.normalizeAddress("zz-83-e7-01-02-0f"))
    }

    func testRequestNeedsAnAddress() throws {
        let packet = try NetworkPacket.parse(#"{"id":1,"type":"flyylink.callaudio.request","body":{"action":"pair","address":"nope"}}"#)

        XCTAssertNil(CallAudio.request(packet))
    }

    func testMuteRoundTrips() throws {
        XCTAssertEqual(Call.request(try wire(Call.mute(true))), Call.Request(.mute))
        XCTAssertEqual(Call.request(try wire(Call.mute(false))), Call.Request(.unmute))
    }
}
