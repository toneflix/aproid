import AppKit
import Foundation
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

    let identity: DeviceIdentity

    private var connected: [String: Device] = [:]
    private var link: LanLink?
    private var timer: Timer?
    private let trustStore = DefaultsTrustStore()

    init() {
        // Menu bar only: no Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)

        identity = DeviceIdentity(
            deviceId: Self.storedDeviceId(),
            deviceName: DeviceIdentity.sanitizeName(Host.current().localizedName ?? "Mac"),
            deviceType: Self.isLaptop() ? .laptop : .desktop
        )

        start()
    }

    func requestPair(_ id: String) { connected[id]?.requestPair() }

    func accept(_ id: String) { connected[id]?.accept() }

    func reject(_ id: String) { connected[id]?.reject() }

    func unpair(_ id: String) { connected[id]?.unpair() }

    private func start() {
        let me = identity
        let trustStore = trustStore

        Task.detached { [weak self] in
            do {
                // Creating the certificate on first launch is slow, so keep it off the main thread.
                let certificate = try Self.loadCertificate(deviceId: me.deviceId)
                let link = try LanLink(identityProvider: { me }, certificate: certificate, trustStore: trustStore) { deviceLink in
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
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            link.broadcastIdentity()
            Task { @MainActor in self?.connected.values.forEach { $0.tick() } }
        }
        link.broadcastIdentity()
    }

    private func failed(_ message: String) {
        error = message
    }

    private func add(_ device: Device) {
        if let old = connected[device.id], old !== device { old.link.close() }

        connected[device.id] = device
        publish()
    }

    fileprivate func remove(_ device: Device) {
        guard connected[device.id] === device else { return }

        connected.removeValue(forKey: device.id)
        publish()
    }

    fileprivate func publish() {
        devices = connected.values
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

        if let der = try? Data(contentsOf: certURL), let pem = try? String(contentsOf: keyURL, encoding: .utf8) {
            return try DeviceCertificate(certificateDER: Array(der), privateKeyPEM: pem)
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
        Task { @MainActor in self.publish() }
    }

    nonisolated func deviceDisconnected(_ device: Device) {
        Task { @MainActor in self.remove(device) }
    }
}
