import Foundation
import FlyyLinkKit

/// Phone notification icons, cached on disk by hash so each one crosses the network once.
final class NotificationIcons {
    private let folder: URL
    private let files = FileManager.default

    init() {
        let caches = files.urls(for: .cachesDirectory, in: .userDomainMask).first ?? files.temporaryDirectory
        folder = caches.appendingPathComponent("FlyyLink/NotificationIcons", isDirectory: true)
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Calls `completion` with a fresh copy of the icon for `packet`, downloading it first if needed,
    /// or with nil when there is none. The copy is the caller's: Notification Center moves it away.
    func icon(for packet: NetworkPacket, hash: String?, from device: Device, completion: @escaping (URL?) -> Void) {
        // The hash becomes a file name, so allow only what an MD5 hash looks like.
        guard let hash, hash.count == 32, hash.allSatisfy(\.isHexDigit) else {
            completion(nil)
            return
        }

        let cached = folder.appendingPathComponent("\(hash).png")
        if files.fileExists(atPath: cached.path) {
            completion(copy(cached))
            return
        }

        guard packet.payloadSize != nil else {
            completion(nil)
            return
        }

        let partial = folder.appendingPathComponent("\(hash).\(UUID().uuidString).part")
        guard files.createFile(atPath: partial.path, contents: nil),
              let sink = try? FileHandle(forWritingTo: partial),
              let download = try? device.receivePayload(packet, into: sink)
        else {
            try? files.removeItem(at: partial)
            completion(nil)
            return
        }

        download.whenComplete { [self] result in
            try? sink.close()

            // Another notification may have brought the same icon meanwhile.
            if case .success = result, !files.fileExists(atPath: cached.path) {
                try? files.moveItem(at: partial, to: cached)
            }
            try? files.removeItem(at: partial)

            completion(files.fileExists(atPath: cached.path) ? copy(cached) : nil)
        }
    }

    private func copy(_ url: URL) -> URL? {
        let target = files.temporaryDirectory.appendingPathComponent("flyylink-icon-\(UUID().uuidString).png")

        return (try? files.copyItem(at: url, to: target)) != nil ? target : nil
    }
}
