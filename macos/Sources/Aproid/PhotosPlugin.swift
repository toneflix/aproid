import Foundation
import AproidKit

/// Receives pages of the phone's gallery ("aproid.photos") and full photos to view ("aproid.photos.file").
final class PhotosPlugin: Plugin {
    let incoming: Set<String> = [PacketType.photos, PacketType.photosFile]

    /// Called on the network thread with each page and the phone it came from.
    var onPage: ((Photos.Page, String) -> Void)?

    /// Called once a photo to view has arrived, with its id, where it was saved, and the phone it came from.
    /// A nil location means it failed.
    var onPreview: ((Int64, URL?, String) -> Void)?

    /// Viewed photos are only kept while the app runs.
    private let cache = FileManager.default.temporaryDirectory.appendingPathComponent("FlyyLink Photos", isDirectory: true)

    init() {
        try? FileManager.default.removeItem(at: cache)
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        if let page = Photos.page(packet) {
            onPage?(page, device.id)
        } else if let file = Photos.file(packet) {
            receive(file, packet: packet, from: device)
        }
    }

    private func receive(_ file: Photos.File, packet: NetworkPacket, from device: Device) {
        let files = FileManager.default
        let target = cache.appendingPathComponent("\(file.id)", isDirectory: true).appendingPathComponent(Share.safeName(file.name))

        try? files.removeItem(at: target)
        guard (try? files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil,
              files.createFile(atPath: target.path, contents: nil),
              let sink = try? FileHandle(forWritingTo: target),
              let download = try? device.receivePayload(packet, into: sink)
        else {
            onPreview?(file.id, nil, device.id)
            return
        }

        download.whenComplete { [weak self] result in
            try? sink.close()

            guard case .success = result else {
                try? files.removeItem(at: target)
                self?.onPreview?(file.id, nil, device.id)
                return
            }

            self?.onPreview?(file.id, target, device.id)
        }
    }
}
