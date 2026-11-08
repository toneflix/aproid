import Foundation
import AproidKit

/// Receives pages of the phone's gallery ("aproid.photos").
final class PhotosPlugin: Plugin {
    let incoming: Set<String> = [PacketType.photos]

    /// Called on the network thread with each page and the phone it came from.
    var onPage: ((Photos.Page, String) -> Void)?

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let page = Photos.page(packet) else { return }

        onPage?(page, device.id)
    }
}
