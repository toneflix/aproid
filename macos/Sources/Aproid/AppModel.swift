import AppKit
import Foundation
import OSLog
import AproidKit

/// What the menu shows for one connected device.
struct DeviceState: Identifiable, Equatable {
    let id: String
    let name: String
    let type: DeviceType
    let host: String
    let pairState: PairState
    let code: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var devices: [DeviceState] = []
    @Published private(set) var error: String?

    /// Notification Center only works when Aproid runs as a bundled app.
    let notificationsAvailable = NotificationPlugin.isAvailable

    let identity: DeviceIdentity

    private let connected = DeviceRegistry()
    private let plugins: PluginRouter
    private var link: LanLink?
    private var timer: Timer?
    private let trustStore = DefaultsTrustStore()
    private let log = Logger(subsystem: "com.toneflix.aproid.app", category: "link")

    /// App Nap would slow the heartbeat timer and make the phone look gone.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Keeps the phone connection alive"
    )

    init() {
        // Menu bar only: no Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)

        identity = DeviceIdentity(
            deviceId: Self.storedDeviceId(),
            deviceName: DeviceIdentity.sanitizeName(Host.current().localizedName ?? "Mac"),
            deviceType: Self.isLaptop() ? .laptop : .desktop
        )
        plugins = PluginRouter([NotificationPlugin(devices: connected)])

        start()
    }

    func requestPair(_ id: String) { connected[id]?.requestPair() }

    func accept(_ id: String) { connected[id]?.accept() }

    func reject(_ id: String) { connected[id]?.reject() }

    func unpair(_ id: String) { connected[id]?.unpair() }

    private func start() {
        let me = identity
        let trustStore = trustStore
        let connected = connected

        Task.detached { [weak self] in
            do {
                // Creating the certificate on first launch is slow, so keep it off the main thread.
                let certificate = try Self.loadCertificate(deviceId: me.deviceId)
                let link = try LanLink(
                    identityProvider: { me },
                    certificate: certificate,
                    trustStore: trustStore,
                    isConnected: { connected[$0]?.link.isOpen == true }
                ) { deviceLink in
                    // Create the device right away on the network thread so no early packet is missed.
                    let device = Device(link: deviceLink, ownCertificate: certificate, trustStore: trustStore)
                    device.delegate = self
                    device.start()
                    Task { @MainActor in self?.add(device) }
                }
                try link.start()

                await self?.started(link)
            } catch {
                await self?.failed("Could not start: \(error)")
            }
        }
    }

    private func started(_ link: LanLink) {
        self.link = link
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            link.broadcastIdentity()
            self?.connected.all.forEach { $0.tick() }
        }
        // Common modes keep it running while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        link.broadcastIdentity()
    }

    private func failed(_ message: String) {
        error = message
    }

    private func add(_ device: Device) {
        if let existing = connected[device.id], existing !== device,
           DeviceLink.keepsExisting(existing.link, over: device.link, ownDeviceId: identity.deviceId) {
            device.link.close(reason: "both sides connected at once; kept the other link")
            return
        }

        if let old = connected.insert(device), old !== device { old.link.close(reason: "replaced by a newer link") }
        log.info("Connected to \(device.name, privacy: .public) (\(device.link.isOutgoing ? "we" : "they", privacy: .public) connected)")
        if device.isPaired { plugins.onPaired(device) }

        publish()
    }

    fileprivate func remove(_ device: Device) {
        guard connected.remove(device) else { return }

        log.info("Disconnected from \(device.name, privacy: .public): \(device.link.closeReason ?? "unknown", privacy: .public)")

        publish()
    }

    fileprivate func publish() {
        devices = connected.all
            .map { device in
                let state = device.pairState
                let showsCode = state == .requested || state == .requestedByPeer

                return DeviceState(
                    id: device.id,
                    name: device.name,
                    type: device.link.identity.deviceType,
                    host: device.link.host,
                    pairState: state,
                    code: showsCode ? device.verificationCode : nil
                )
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: Storage

    private static func storedDeviceId() -> String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "deviceId") { return id }

        let id = DeviceIdentity.newDeviceId()
        defaults.set(id, forKey: "deviceId")

        return id
    }

    private nonisolated static func loadCertificate(deviceId: String) throws -> DeviceCertificate {
        let files = FileManager.default
        let folder = try files
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Aproid", isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)

        let certURL = folder.appendingPathComponent("device.crt")
        let keyURL = folder.appendingPathComponent("device.key")

        // Reuse the stored certificate only if it belongs to this device id. Peers refuse
        // a certificate whose common name differs from the id we announce.
        if let der = try? Data(contentsOf: certURL),
           let pem = try? String(contentsOf: keyURL, encoding: .utf8),
           let stored = try? DeviceCertificate(certificateDER: Array(der), privateKeyPEM: pem),
           stored.deviceId == deviceId {
            return stored
        }

        let certificate = try DeviceCertificate.generate(deviceId: deviceId)
        try Data(certificate.certificateDER).write(to: certURL)
        try certificate.privateKeyPEM.write(to: keyURL, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)

        return certificate
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

extension AppModel: DeviceDelegate {
    nonisolated func devicePairRequested(_ device: Device, code: String) {
        Task { @MainActor in
            self.publish()
            NSApplication.shared.requestUserAttention(.informationalRequest)
        }
    }

    nonisolated func device(_ device: Device, pairStateChanged state: PairState) {
        if state == .paired { plugins.onPaired(device) }

        Task { @MainActor in self.publish() }
    }

    nonisolated func device(_ device: Device, received packet: NetworkPacket) {
        plugins.dispatch(packet, from: device)
    }

    nonisolated func deviceDisconnected(_ device: Device) {
        Task { @MainActor in self.remove(device) }
    }
}
