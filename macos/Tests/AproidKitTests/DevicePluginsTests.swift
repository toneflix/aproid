import XCTest
@testable import AproidKit

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

    func testClipboardContentComesFromBothPacketTypes() {
        XCTAssertEqual(Clipboard.content(Clipboard.packet("hello")), "hello")
        XCTAssertEqual(Clipboard.content(Clipboard.connectPacket("hello", timestampMillis: 1_700_000_000_000)), "hello")
        XCTAssertNil(Clipboard.content(Clipboard.packet("")))
        XCTAssertNil(Clipboard.content(FindMyPhone.request()))
    }
}
