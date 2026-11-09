import XCTest
@testable import AproidKit

final class DeviceFocusTests: XCTestCase {
    private struct Peer: Equatable {
        let id: String
        let name: String
    }

    private let devices = [Peer(id: "c", name: "Pixel"), Peer(id: "a", name: "Galaxy"), Peer(id: "b", name: "Pixel")]

    private func pick(_ preferredId: String?, _ list: [Peer]? = nil) -> Peer? {
        DeviceFocus(preferredId: preferredId).pick(list ?? devices, id: \.id, name: \.name)
    }

    func testPreferredDeviceWins() {
        XCTAssertEqual(pick("c"), Peer(id: "c", name: "Pixel"))
    }

    func testFallsBackToFirstByName() {
        XCTAssertEqual(pick(nil), Peer(id: "a", name: "Galaxy"))
    }

    func testMissingPreferredFallsBack() {
        XCTAssertEqual(pick("gone"), Peer(id: "a", name: "Galaxy"))
    }

    func testSameNamesAreOrderedById() {
        XCTAssertEqual(pick(nil, [Peer(id: "c", name: "Pixel"), Peer(id: "b", name: "Pixel")]), Peer(id: "b", name: "Pixel"))
    }

    func testNoDevicesPicksNothing() {
        XCTAssertNil(pick("a", []))
    }
}
