import XCTest
@testable import FlyyLinkKit

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

    private func next(_ preferredId: String?, _ list: [Peer]? = nil) -> Peer? {
        DeviceFocus(preferredId: preferredId).next(list ?? devices, id: \.id, name: \.name)
    }

    func testNextFollowsNameOrder() {
        XCTAssertEqual(next("a"), Peer(id: "b", name: "Pixel"))
        XCTAssertEqual(next("b"), Peer(id: "c", name: "Pixel"))
    }

    func testNextWrapsToFirst() {
        XCTAssertEqual(next("c"), Peer(id: "a", name: "Galaxy"))
    }

    func testNextWithoutPreferredStartsAtFirst() {
        XCTAssertEqual(next("gone"), Peer(id: "a", name: "Galaxy"))
        XCTAssertNil(next("a", []))
    }

    func testNoDevicesPicksNothing() {
        XCTAssertNil(pick("a", []))
    }
}
