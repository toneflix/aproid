import Foundation
import FlyyLinkKit

/// Connected devices by id, safe to read from any thread.
final class DeviceRegistry {
    private var devices: [String: Device] = [:]
    private let lock = NSLock()

    subscript(id: String) -> Device? {
        lock.withLock { devices[id] }
    }

    var all: [Device] {
        lock.withLock { Array(devices.values) }
    }

    /// Stores the device and returns the one it replaced, if any.
    @discardableResult
    func insert(_ device: Device) -> Device? {
        lock.withLock { devices.updateValue(device, forKey: device.id) }
    }

    /// Removes the device only if it is still the current one for its id.
    func remove(_ device: Device) -> Bool {
        lock.withLock {
            guard devices[device.id] === device else { return false }

            devices.removeValue(forKey: device.id)
            return true
        }
    }
}
