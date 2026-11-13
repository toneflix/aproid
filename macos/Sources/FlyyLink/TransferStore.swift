import Foundation

/// Files that haven't finished moving, kept on disk so a transfer can still resume after FlyyLink quits.
final class TransferStore: @unchecked Sendable {
    /// A file we offered to the phone, which it may ask the rest of.
    struct Offered: Codable {
        let path: String
        let deviceId: String
        let deviceName: String
        let expires: Date
    }

    /// A file partly received from the phone.
    struct Partial: Codable {
        let path: String
        let deviceId: String
        let deviceName: String
        let total: Int64
        let expires: Date
    }

    private struct Contents: Codable {
        var offered: [String: Offered] = [:]
        var partial: [String: Partial] = [:]
    }

    /// How long an unfinished file waits for the other side to come back.
    static let keep: TimeInterval = 24 * 60 * 60

    private let file: URL
    private let lock = NSLock()
    private var contents: Contents

    init(file: URL = TransferStore.defaultFile) {
        self.file = file
        contents = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Contents.self, from: $0) } ?? Contents()
    }

    var offered: [String: Offered] { lock.withLock { contents.offered } }

    var partial: [String: Partial] { lock.withLock { contents.partial } }

    func setOffered(_ id: String, _ value: Offered?) {
        change { $0.offered[id] = value }
    }

    func setPartial(_ id: String, _ value: Partial?) {
        change { $0.partial[id] = value }
    }

    /// Drops what has expired and returns the partial files it dropped, so their bytes can be deleted.
    func removeExpired(now: Date = Date()) -> [Partial] {
        var dropped: [Partial] = []

        change { contents in
            contents.offered = contents.offered.filter { $0.value.expires > now }
            dropped = contents.partial.values.filter { $0.expires <= now }
            contents.partial = contents.partial.filter { $0.value.expires > now }
        }

        return dropped
    }

    private func change(_ update: (inout Contents) -> Void) {
        let data = lock.withLock { () -> Data? in
            update(&contents)
            return try? JSONEncoder().encode(contents)
        }

        guard let data else { return }

        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlyyLink", isDirectory: true)
            .appendingPathComponent("transfers.json")
    }
}
