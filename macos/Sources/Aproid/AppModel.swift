import AppKit
import Foundation
import Network
import AproidKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var peers: [DiscoveredPeer] = []
    let identity: DeviceIdentity
    private var link: LanLink?
    private var timer: Timer?

    init() {
        // Menu bar only: no Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)

        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: "deviceId") ?? {
            let new = DeviceIdentity.newDeviceId()
            defaults.set(new, forKey: "deviceId")
            return new
        }()
        identity = DeviceIdentity(
            deviceId: id,
            deviceName: DeviceIdentity.sanitizeName(Host.current().localizedName ?? "Mac"),
            deviceType: Self.isLaptop() ? .laptop : .desktop
        )

        let me = identity
        let link = LanLink(identityProvider: { me }) { [weak self] peer, _ in
            // TODO: upgrade the connection to TLS and hand it to a Device object (see docs/ARCHITECTURE.md).
            Task { @MainActor in self?.add(peer) }
        }
        self.link = link
        link.start()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            link.broadcastIdentity()
        }
    }

    private func add(_ peer: DiscoveredPeer) {
        peers.removeAll { $0.identity.deviceId == peer.identity.deviceId }
        peers.append(peer)
    }

    private static func isLaptop() -> Bool {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return false }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model).contains("Book")
    }
}
