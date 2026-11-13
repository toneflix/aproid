import Foundation
import FlyyLinkKit

/// Passes a phone's notifications and calls on to paired computers that aren't connected to it, and their
/// replies and call buttons back to the phone ("flyylink.relay").
final class PhoneRelayPlugin: Plugin {
    let incoming: Set<String> = Relay.fromPhone.union([PacketType.relay])

    /// Called on a network thread with a phone's packet that another computer passed on, and that computer's name.
    var onRelayed: ((Relay.Message, String) -> Void)?

    private let devices: DeviceRegistry
    private let defaults = UserDefaults.standard
    private static let enabledKey = "relaysPhones"
    private let lock = NSLock()

    /// Which computer each relayed phone is reached through.
    private var routes: [String: String] = [:]

    init(devices: DeviceRegistry) {
        self.devices = devices
    }

    /// Whether phones are passed on to and from other computers.
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard isEnabled else { return }

        if device.link.identity.deviceType.isComputer {
            if let message = Relay.message(packet) { received(message, from: device) }
            return
        }

        guard Relay.fromPhone.contains(packet.type) else { return }

        let wrapped = Relay.wrap(packet, phoneId: device.id, phoneName: device.name)
        for computer in devices.all where computer.isPaired && computer.link.identity.deviceType.isComputer {
            computer.send(wrapped)
        }
    }

    /// Sends a packet to a phone this Mac only reaches through another computer. False when there is no route.
    func send(_ packet: NetworkPacket, toPhone phoneId: String) -> Bool {
        guard isEnabled, Relay.toPhone.contains(packet.type),
              let via = lock.withLock({ routes[phoneId] }), let computer = devices[via], computer.isPaired
        else { return false }

        return computer.send(Relay.wrap(packet, phoneId: phoneId, phoneName: ""))
    }

    /// A computer disconnected: phones reached through it are gone too.
    func forget(_ deviceId: String) {
        lock.withLock { routes = routes.filter { $0.value != deviceId } }
    }

    private func received(_ message: Relay.Message, from computer: Device) {
        if Relay.toPhone.contains(message.packet.type) {
            guard let phone = devices[message.phoneId], phone.isPaired, phone.link.identity.deviceType.isPhone else { return }

            phone.send(message.packet)
            return
        }

        // Connected to the phone directly, so this already arrived first hand.
        if devices[message.phoneId]?.isPaired == true { return }

        lock.withLock { routes[message.phoneId] = computer.id }
        onRelayed?(message, computer.name)
    }
}
