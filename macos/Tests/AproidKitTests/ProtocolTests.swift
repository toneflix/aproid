import XCTest
@testable import AproidKit

final class NetworkPacketTests: XCTestCase {
    func testSerializeEndsWithNewlineAndRoundTrips() throws {
        let p = NetworkPacket(type: PacketType.ping, body: ["message": "hi"], id: 42)
        let data = try p.serialize()
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(data.filter { $0 == 0x0A }.count, 1)
        XCTAssertEqual(try NetworkPacket.parse(data), p)
    }

    func testParsesStringId() throws {
        let p = try NetworkPacket.parse(#"{"id":"123","type":"kdeconnect.ping","body":{}}"#)
        XCTAssertEqual(p.id, 123)
    }

    func testPayloadFields() throws {
        let p = NetworkPacket(type: PacketType.shareRequest, body: ["filename": "a.jpg"], id: 1,
                              payloadSize: 2048, payloadTransferInfo: ["port": 1739])
        let back = try NetworkPacket.parse(try p.serialize())
        XCTAssertEqual(back.payloadSize, 2048)
        XCTAssertEqual(back.payloadTransferInfo?["port"]?.intValue, 1739)
    }

    func testRejectsMissingType() {
        XCTAssertThrowsError(try NetworkPacket.parse(#"{"id":1,"body":{}}"#))
        XCTAssertThrowsError(try NetworkPacket.parse("not json"))
    }

    /// The same bytes the Kotlin side produces must parse here.
    func testReadsKotlinStylePacket() throws {
        let wire = #"{"id":1700000000000,"type":"kdeconnect.identity","body":{"deviceId":"_0123456789abcdef0123456789abcdef_","deviceName":"Pixel","deviceType":"phone","protocolVersion":8,"incomingCapabilities":["kdeconnect.ping"],"outgoingCapabilities":[],"tcpPort":1716}}"#
        let id = try DeviceIdentity(packet: try NetworkPacket.parse(wire))
        XCTAssertEqual(id.deviceType, .phone)
        XCTAssertEqual(id.tcpPort, 1716)
        XCTAssertEqual(id.incomingCapabilities, ["kdeconnect.ping"])
    }
}

final class DeviceIdentityTests: XCTestCase {
    func testNewIdsAreValid() {
        for _ in 0..<20 { XCTAssertTrue(DeviceIdentity.isValidDeviceId(DeviceIdentity.newDeviceId())) }
        XCTAssertFalse(DeviceIdentity.isValidDeviceId("short"))
    }

    func testSanitizesNames() {
        XCTAssertEqual(DeviceIdentity.sanitizeName("Obi's MacBook!"), "Obis MacBook")
        XCTAssertEqual(DeviceIdentity.sanitizeName("..."), "Mac")
        XCTAssertEqual(DeviceIdentity.sanitizeName(String(repeating: "x", count: 50)).count, 32)
    }

    func testRoundTrip() throws {
        let id = DeviceIdentity(deviceId: DeviceIdentity.newDeviceId(), deviceName: "Mac", deviceType: .laptop, tcpPort: 1716)
        let back = try DeviceIdentity(packet: try NetworkPacket.parse(try id.toPacket().serialize()))
        XCTAssertEqual(back, id)
    }

    func testTellsComputersFromPhones() {
        XCTAssertTrue(DeviceType.laptop.isComputer)
        XCTAssertTrue(DeviceType.desktop.isComputer)
        XCTAssertFalse(DeviceType.phone.isComputer)
        XCTAssertTrue(DeviceType.tablet.isPhone)
        XCTAssertFalse(DeviceType.tv.isPhone)
    }
}

final class PairingTests: XCTestCase {
    private func pair(_ value: Bool, _ ts: Int64? = nil) -> NetworkPacket {
        var body: [String: JSONValue] = ["pair": .bool(value)]
        if let ts { body["timestamp"] = .int(ts) }
        return NetworkPacket(type: PacketType.pair, body: body)
    }

    func testWeRequestAndPeerAccepts() {
        let sm = PairingStateMachine()
        guard case .send(let p) = sm.requestPair(now: 1000) else { return XCTFail() }
        XCTAssertEqual(p.int("timestamp"), 1000)
        XCTAssertEqual(sm.handle(pair(true), now: 1005), .paired)
        XCTAssertEqual(sm.state, .paired)
    }

    func testPeerRequestsAndUserAccepts() {
        let sm = PairingStateMachine()
        XCTAssertEqual(sm.handle(pair(true, 1000), now: 1001), .askUser)
        guard case .send(let p) = sm.accept() else { return XCTFail() }
        XCTAssertEqual(p.bool("pair"), true)
        XCTAssertEqual(sm.state, .paired)
    }

    func testStaleTimestampIsRefused() {
        let sm = PairingStateMachine()
        guard case .send(let p) = sm.handle(pair(true, 0), now: 100_000) else { return XCTFail() }
        XCTAssertEqual(p.bool("pair"), false)
        XCTAssertEqual(sm.state, .notPaired)
    }

    func testRequestTimesOut() {
        let sm = PairingStateMachine()
        _ = sm.requestPair(now: 0)
        XCTAssertEqual(sm.tick(now: 10), .none)
        XCTAssertEqual(sm.tick(now: 31), .unpaired)
    }
}
