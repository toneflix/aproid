import XCTest
@testable import AproidKit

final class PhotosTests: XCTestCase {
    private func wire(_ packet: NetworkPacket) throws -> NetworkPacket {
        try NetworkPacket.parse(try packet.serialize())
    }

    func testPageRoundTrips() throws {
        let photos = [
            PhonePhoto(id: 12, name: "IMG_2041.jpg", date: 1_700_000_000_000, mimeType: "image/jpeg", width: 4000, height: 3000, size: 2_400_000, thumbnail: "aGVsbG8="),
            PhonePhoto(id: 13, name: "VID_0007.mp4", date: 1_700_000_100_000, mimeType: "video/mp4"),
        ]

        XCTAssertEqual(Photos.page(try wire(Photos.pagePacket(photos, more: true))), Photos.Page(photos: photos, more: true))
        XCTAssertTrue(photos[1].isVideo)
    }

    func testRequestsRoundTrip() throws {
        XCTAssertEqual(Photos.request(try wire(Photos.request(before: 1_700_000_000_000))), Photos.Request(before: 1_700_000_000_000, count: 40))
        XCTAssertEqual(Photos.request(try wire(Photos.request(count: 5000))), Photos.Request(before: nil, count: 200))
        XCTAssertEqual(Photos.downloadId(try wire(Photos.download(id: 12))), 12)
        XCTAssertNil(Photos.downloadId(Photos.request()))
    }
}
