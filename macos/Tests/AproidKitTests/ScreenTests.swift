import XCTest
@testable import AproidKit

final class ScreenTests: XCTestCase {
    private func wire(_ packet: NetworkPacket) throws -> NetworkPacket {
        try NetworkPacket.parse(try packet.serialize())
    }

    func testRequestsRoundTripWithinLimits() throws {
        XCTAssertEqual(Screen.request(try wire(Screen.start(maxSize: 1280, bitrate: 4_000_000))), Screen.Request(action: .start, maxSize: 1280, bitrate: 4_000_000))
        XCTAssertEqual(Screen.request(try wire(Screen.start(maxSize: 99_999, bitrate: 900_000_000))), Screen.Request(action: .start, maxSize: 4096, bitrate: 50_000_000))
        XCTAssertEqual(Screen.request(try wire(Screen.stop()))?.action, .stop)
        XCTAssertEqual(Screen.info(try wire(Screen.started(width: 1080, height: 2400))), Screen.Info(width: 1080, height: 2400, running: true))
        XCTAssertEqual(Screen.info(try wire(Screen.stopped()))?.running, false)
    }

    func testInputRoundTripsAndRejectsNonsense() throws {
        let inputs: [ScreenInput] = [
            .tap(x: 0.5, y: 0.25),
            .longPress(x: 0, y: 1),
            .swipe(x: 0.5, y: 0.8, toX: 0.5, toY: 0.2, durationMs: 300),
            .text("hello"),
            .key(ScreenInput.back),
            .key(ScreenInput.wordLeft, select: true),
            .key(ScreenInput.selectAll),
        ]

        for input in inputs {
            XCTAssertEqual(ScreenInput(packet: try wire(input.toPacket())), input)
        }
        XCTAssertNil(ScreenInput(packet: try wire(ScreenInput.tap(x: 1.5, y: 0.2).toPacket())))
        XCTAssertNil(ScreenInput(packet: try wire(ScreenInput.key("reboot").toPacket())))
    }

    func testReaderRebuildsFramesSplitAnywhere() throws {
        let frames = [
            ScreenFrame(data: Data([0, 0, 0, 1, 0x67]), timeUs: 0, flags: ScreenFrame.config),
            ScreenFrame(data: Data((0..<5000).map { UInt8($0 % 256) }), timeUs: 33_333, flags: ScreenFrame.key),
            ScreenFrame(data: Data([9, 9]), timeUs: 50_000, flags: 0),
        ]
        let stream = frames.reduce(Data()) { $0 + $1.header() + $1.data }
        let reader = ScreenFrameReader()

        var out: [ScreenFrame] = []
        for start in stride(from: 0, to: stream.count, by: 7) {
            out += try reader.feed(stream.subdata(in: start..<min(start + 7, stream.count)))
        }

        XCTAssertEqual(out, frames)
        XCTAssertTrue(out[0].isConfig && out[1].isKey)
    }

    func testHeaderMatchesTheKotlinLayout() {
        let header = ScreenFrame(data: Data(count: 258), timeUs: 1, flags: ScreenFrame.key).header()

        XCTAssertEqual([UInt8](header), [0, 0, 1, 2, 0, 0, 0, 0, 0, 0, 0, 1, 2])
    }
}
