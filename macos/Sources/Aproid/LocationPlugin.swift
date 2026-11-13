import Foundation
import AproidKit

/// Remembers where each phone last said it was ("flyylink.location").
final class LocationPlugin: Plugin {
    let incoming: Set<String> = [PacketType.location]

    /// Called on any thread when a phone reports a new location.
    var onChange: (() -> Void)?

    private var locations: [String: PhoneLocation] = [:]
    private let lock = NSLock()

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let location = PhoneLocation(packet: packet) else { return }

        lock.withLock {
            // A fresh fix can arrive before the older last known one; keep the newest.
            if let known = locations[device.id], known.time > location.time { return }
            locations[device.id] = location
        }
        onChange?()
    }

    func location(for deviceId: String) -> PhoneLocation? {
        lock.withLock { locations[deviceId] }
    }

    func request(from device: Device) {
        device.send(PhoneLocation.request())
    }
}
