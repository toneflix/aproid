import Foundation
import UserNotifications
import AproidKit

/// Keeps each phone's battery level for the menu, and alerts when a phone runs low.
final class BatteryPlugin: Plugin {
    let incoming: Set<String> = [PacketType.battery]

    private var levels: [String: BatteryStatus] = [:]
    private let lock = NSLock()

    /// Called on a networking thread when a level changes. Set it before the link starts.
    var onChange: (() -> Void)?

    func status(for deviceId: String) -> BatteryStatus? {
        lock.withLock { levels[deviceId] }
    }

    func onPaired(_ device: Device) {
        device.send(BatteryStatus.request())
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let status = BatteryStatus(packet: packet) else { return }

        let wasLow = lock.withLock { levels.updateValue(status, forKey: device.id)?.isLow ?? false }
        if status.isLow && !wasLow { alertLow(device.name, charge: status.charge) }

        onChange?()
    }

    private func alertLow(_ name: String, charge: Int) {
        guard NotificationPlugin.isAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(name) battery is low"
        content.body = "\(charge)% left. Plug it in soon."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "battery.\(name)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
