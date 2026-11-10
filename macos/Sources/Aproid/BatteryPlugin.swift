import Foundation
import UserNotifications
import AproidKit

/// Keeps each device's battery level for the menu and alerts when a phone runs low. Tells paired devices this Mac's own level.
final class BatteryPlugin: Plugin {
    let incoming: Set<String> = [PacketType.battery, PacketType.batteryRequest]

    private var levels: [String: BatteryStatus] = [:]
    private var lastSent: BatteryStatus?
    private let lock = NSLock()
    private let devices: DeviceRegistry
    private let own = SystemBattery()

    /// Called on a networking thread when a level changes. Set it before the link starts.
    var onChange: (() -> Void)?

    init(devices: DeviceRegistry) {
        self.devices = devices
        own.onChange = { [weak self] in self?.ownChanged() }
        own.start()
    }

    func status(for deviceId: String) -> BatteryStatus? {
        lock.withLock { levels[deviceId] }
    }

    func onPaired(_ device: Device) {
        device.send(BatteryStatus.request())
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        if packet.type == PacketType.batteryRequest {
            if let status = SystemBattery.current() { device.send(status.toPacket()) }
            return
        }

        guard let status = BatteryStatus(packet: packet) else { return }

        let wasLow = lock.withLock { levels.updateValue(status, forKey: device.id)?.isLow ?? false }
        if status.isLow && !wasLow { alertLow(device.name, charge: status.charge) }

        onChange?()
    }

    /// Sends this Mac's level to every paired device when it moves.
    private func ownChanged() {
        guard let status = SystemBattery.current() else { return }

        let changed = lock.withLock { () -> Bool in
            guard lastSent != status else { return false }

            lastSent = status
            return true
        }
        guard changed else { return }

        devices.all.filter(\.isPaired).forEach { $0.send(status.toPacket()) }
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
