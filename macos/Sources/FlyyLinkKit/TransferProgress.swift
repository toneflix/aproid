import Foundation

/// Tracks how far a file transfer has got, how fast it is moving and how long is left.
/// Safe to advance from a network thread and read from the UI. Mirrors TransferProgress.kt.
public final class TransferProgress: @unchecked Sendable {
    /// One reading, safe to hand to the UI.
    public struct Snapshot: Equatable, Sendable {
        public let done: Int64
        public let total: Int64
        public let bytesPerSecond: Int64?
        public let secondsLeft: Int64?

        public var fraction: Double { total <= 0 ? 1 : min(max(Double(done) / Double(total), 0), 1) }
    }

    private static let reportEveryNanos: UInt64 = 100_000_000

    /// Speed reads wildly in the first moments, so it is held back until then.
    private static let minSeconds = 1.0

    public let total: Int64
    private let clock: () -> UInt64
    private let startedAt: UInt64
    private let startedWith: Int64
    private var done: Int64
    private var reportedAt: UInt64
    private let lock = NSLock()

    public init(total: Int64, alreadyDone: Int64 = 0, clock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.total = total
        self.clock = clock
        startedAt = clock()
        startedWith = min(max(alreadyDone, 0), max(total, 0))
        done = startedWith
        reportedAt = startedAt
    }

    /// Adds `bytes` and returns a reading when the UI is due one, about ten times a second.
    public func advance(_ bytes: Int64) -> Snapshot? {
        lock.withLock {
            done = min(done + bytes, total)
            let now = clock()
            guard now - reportedAt >= Self.reportEveryNanos || done >= total else { return nil }

            reportedAt = now
            return snapshot(at: now)
        }
    }

    public func snapshot() -> Snapshot {
        lock.withLock { snapshot(at: clock()) }
    }

    private func snapshot(at now: UInt64) -> Snapshot {
        let seconds = Double(now - startedAt) / 1e9
        let moved = done - startedWith
        let speed = seconds >= Self.minSeconds && moved > 0 ? max(Int64(Double(moved) / seconds), 1) : nil
        let left = speed.map { Int64((Double(total - done) / Double($0)).rounded(.up)) }

        return Snapshot(done: done, total: total, bytesPerSecond: speed, secondsLeft: left)
    }
}
