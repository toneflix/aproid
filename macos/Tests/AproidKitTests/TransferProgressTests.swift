import XCTest
@testable import AproidKit

final class TransferProgressTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        var now: UInt64 = 0
    }

    private let second: UInt64 = 1_000_000_000

    func testReportsAboutTenTimesASecond() {
        let clock = Clock()
        let progress = TransferProgress(total: 1000) { clock.now }

        XCTAssertNil(progress.advance(10))

        clock.now += second / 10
        XCTAssertNotNil(progress.advance(10))
        XCTAssertNil(progress.advance(10))
    }

    func testAlwaysReportsTheLastBytes() {
        let progress = TransferProgress(total: 100) { 0 }

        XCTAssertEqual(progress.advance(100)?.fraction, 1)
    }

    func testHoldsSpeedBackForTheFirstSecond() {
        let clock = Clock()
        let progress = TransferProgress(total: 1000) { clock.now }

        clock.now += second / 2
        let early = progress.advance(100)

        XCTAssertNil(early?.bytesPerSecond)
        XCTAssertNil(early?.secondsLeft)
    }

    func testMeasuresSpeedAndTimeLeft() {
        let clock = Clock()
        let progress = TransferProgress(total: 1000) { clock.now }

        clock.now += 2 * second
        let reading = progress.advance(200)

        XCTAssertEqual(reading, TransferProgress.Snapshot(done: 200, total: 1000, bytesPerSecond: 100, secondsLeft: 8))
        XCTAssertEqual(reading?.fraction ?? 0, 0.2, accuracy: 0.0001)
    }

    func testResumedTransferCountsOnlyNewBytesForSpeed() {
        let clock = Clock()
        let progress = TransferProgress(total: 1000, alreadyDone: 600) { clock.now }

        clock.now += 2 * second
        let reading = progress.advance(100)

        XCTAssertEqual(reading, TransferProgress.Snapshot(done: 700, total: 1000, bytesPerSecond: 50, secondsLeft: 6))
    }
}
