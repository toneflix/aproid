import XCTest
@testable import FlyyLinkKit

final class TvRemoteTests: XCTestCase {
    private func wire(_ packet: NetworkPacket) throws -> NetworkPacket {
        try NetworkPacket.parse(try packet.serialize())
    }

    func testKeysAndTextRoundTrip() throws {
        for key in TvRemote.keys {
            XCTAssertEqual(TvRemote(packet: try wire(TvRemote.key(key).toPacket())), .key(key))
        }
        XCTAssertEqual(TvRemote(packet: try wire(TvRemote.text("hello").toPacket())), .text("hello"))
        XCTAssertEqual(TvRemote.key(TvRemote.playPause).toPacket().string("key"), "playPause")
    }

    func testRejectsNonsense() throws {
        XCTAssertNil(TvRemote(packet: try wire(TvRemote.key("launchMissiles").toPacket())))
        XCTAssertNil(TvRemote(packet: try wire(TvRemote.text("").toPacket())))
        XCTAssertNil(TvRemote(packet: try wire(TvRemote.text(String(repeating: "x", count: TvRemote.maxText + 1)).toPacket())))
        XCTAssertNil(TvRemote(packet: NetworkPacket(type: PacketType.remote, body: ["action": "fly"])))
        XCTAssertNil(TvRemote(packet: NetworkPacket(type: PacketType.ping)))
    }

    func testTvsSkipPhoneAndComputerFeatures() {
        XCTAssertTrue(Capabilities.mvp.contains(PacketType.remote))
        XCTAssertTrue(Capabilities.tv.isSuperset(of: [PacketType.remote, PacketType.shareRequest, PacketType.notification, PacketType.mprisRequest, PacketType.flyyDropRequest]))
        XCTAssertFalse(Capabilities.tv.contains(PacketType.smsRequest))
        XCTAssertFalse(Capabilities.tv.contains(PacketType.telephony))
        XCTAssertFalse(Capabilities.tv.contains(PacketType.clipboard))
        XCTAssertFalse(Capabilities.tv.contains(PacketType.screenRequest))
        XCTAssertFalse(Capabilities.tv.contains(PacketType.battery))
        XCTAssertTrue(Capabilities.mvp.isSuperset(of: Capabilities.tv))
    }

    func testCapabilitiesFollowTheDeviceType() {
        XCTAssertEqual(Capabilities.forType(.tv), Capabilities.tv)
        XCTAssertEqual(Capabilities.forType(.phone), Capabilities.mvp)
        XCTAssertEqual(Capabilities.forType(.laptop), Capabilities.mvp)
    }
}
