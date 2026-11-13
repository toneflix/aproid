import XCTest
@testable import FlyyLinkKit

final class DevicePluginsTests: XCTestCase {
    func testBatteryRoundTrips() throws {
        let status = BatteryStatus(charge: 42, isCharging: true)

        let back = BatteryStatus(packet: try NetworkPacket.parse(status.toPacket().serialize()))

        XCTAssertEqual(back, status)
    }

    func testBatteryIsLowOnlyWhenNotCharging() {
        XCTAssertTrue(BatteryStatus.of(charge: 15, isCharging: false).isLow)
        XCTAssertFalse(BatteryStatus.of(charge: 15, isCharging: true).isLow)
        XCTAssertFalse(BatteryStatus.of(charge: 16, isCharging: false).isLow)
    }

    func testReadsKdeConnectBatteryPacket() throws {
        let wire = #"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":9,"isCharging":false,"thresholdEvent":1}}"#

        let status = BatteryStatus(packet: try NetworkPacket.parse(Data(wire.utf8)))

        XCTAssertEqual(status, BatteryStatus(charge: 9, isCharging: false, isLow: true))
    }

    func testResumedFileCarriesItsTransferAndOffset() throws {
        var packet = Share.filePacket(name: "film.mp4", size: 1000, transferId: "t1", offset: 400)
        packet.payloadSize = 600
        let resumed = try NetworkPacket.parse(try packet.serialize())

        XCTAssertEqual(Share(packet: resumed), .file(name: "film.mp4", size: 600, transferId: "t1", offset: 400))

        let request = Share.resumeRequest(try NetworkPacket.parse(try Share.resumePacket(transferId: "t1", offset: 400).serialize()))
        XCTAssertEqual(request?.transferId, "t1")
        XCTAssertEqual(request?.offset, 400)
        XCTAssertNil(Share.resumeRequest(Share.linkPacket("https://example.com")))
    }

    func testLocationRoundTripsAndRejectsNonsense() throws {
        let here = PhoneLocation(latitude: 6.5244, longitude: 3.3792, accuracy: 12.5, time: 1_700_000_000_000)

        XCTAssertEqual(PhoneLocation(packet: try NetworkPacket.parse(try here.toPacket().serialize())), here)
        XCTAssertNil(PhoneLocation(packet: PhoneLocation(latitude: 95, longitude: 3, accuracy: 1, time: 0).toPacket()))
        XCTAssertEqual(PhoneLocation.request().type, PacketType.locationRequest)
    }

    func testClipboardFileNeedsAPayload() throws {
        var announced = Clipboard.filePacket(name: "../shot.png", mimeType: "image/png")

        XCTAssertNil(Clipboard.file(announced))

        announced.payloadSize = 10
        let withPayload = try NetworkPacket.parse(try announced.serialize())
        XCTAssertEqual(Clipboard.file(withPayload), ClipboardFile(name: "../shot.png", mimeType: "image/png"))
        XCTAssertEqual(Clipboard.file(withPayload)?.safeName, "shot.png")
    }

    func testClipboardContentComesFromBothPacketTypes() {
        XCTAssertEqual(Clipboard.content(Clipboard.packet("hello")), "hello")
        XCTAssertEqual(Clipboard.content(Clipboard.connectPacket("hello", timestampMillis: 1_700_000_000_000)), "hello")
        XCTAssertNil(Clipboard.content(Clipboard.packet("")))
        XCTAssertNil(Clipboard.content(FindMyPhone.request()))
    }

    func testSharePacketsParse() {
        var file = Share.filePacket(name: "a.txt", size: 5)
        file.payloadSize = 5

        XCTAssertEqual(Share(packet: file), .file(name: "a.txt", size: 5))
        XCTAssertEqual(Share(packet: Share.linkPacket("https://example.com")), .link("https://example.com"))
        XCTAssertEqual(Share(packet: Share.textPacket("hi")), .text("hi"))
    }

    func testSharedFileNameCannotLeaveTheFolder() {
        XCTAssertEqual(Share.safeName("../../etc/passwd"), "passwd")
        XCTAssertEqual(Share.safeName("C:\\evil.txt"), "evil.txt")
        XCTAssertEqual(Share.safeName(".."), "file")
    }
}
