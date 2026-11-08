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
    let battery: BatteryStatus?
    let media: NowPlaying?
}

@MainActor
final class AppModel: ObservableObject {
    /// One model for the whole app, so the app delegate can reach it for tel: links.
    static let shared = AppModel()

    @Published private(set) var devices: [DeviceState] = []
    @Published private(set) var error: String?
    @Published private(set) var recent: [Activity] = []
    @Published private(set) var clipboardSyncedAt: Date?
    @Published private(set) var notificationsToday = 0
    @Published private(set) var call: ActiveCall?
    @Published var mirrorsNotifications: Bool {
        didSet {
            notifications.isEnabled = mirrorsNotifications
            UserDefaults.standard.set(mirrorsNotifications, forKey: "mirrorsNotifications")
        }
    }

    static let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    /// Notification Center only works when Aproid runs as a bundled app.
    let notificationsAvailable = NotificationPlugin.isAvailable

    let identity: DeviceIdentity

    private let connected = DeviceRegistry()
    private let plugins: PluginRouter
    private let battery = BatteryPlugin()
    private let clipboard: ClipboardPlugin
    private let notifications: NotificationPlugin
    private let share = SharePlugin(folder: AppModel.downloads)
    private let mediaPlugin = MediaPlugin()
    private let sms = SmsPlugin()
    private let calls = CallPlugin()
    private let callPanel = CallPanel()
    private var messagesDevice: String?

    let messages = MessagesStore()
    private var notificationsDay = Calendar.current.startOfDay(for: Date())
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
        clipboard = ClipboardPlugin(devices: connected)
        notifications = NotificationPlugin(devices: connected)
        plugins = PluginRouter([notifications, battery, clipboard, share, mediaPlugin, sms, calls])
        mirrorsNotifications = UserDefaults.standard.object(forKey: "mirrorsNotifications") as? Bool ?? true
        notifications.isEnabled = mirrorsNotifications

        battery.onChange = { [weak self] in Task { @MainActor in self?.publish() } }
        mediaPlugin.onChange = { [weak self] in Task { @MainActor in self?.publish() } }
        sms.onMessages = { [weak self] messages, deviceId in Task { @MainActor in self?.messages.ingest(messages, from: deviceId) } }
        calls.onState = { [weak self] state, device in
            let deviceId = device.id
            let deviceName = device.name
            Task { @MainActor in self?.handleCall(state, deviceId: deviceId, deviceName: deviceName) }
        }
        messages.send = { [weak self] packet in
            guard let id = self?.messagesDevice, let device = self?.connected[id] else { return false }
            return device.send(packet)
        }
        clipboard.onSync = { [weak self] in Task { @MainActor in self?.clipboardSyncedAt = Date() } }
        notifications.onShown = { [weak self] in Task { @MainActor in self?.countNotification() } }
        share.onActivity = { [weak self] activity in Task { @MainActor in self?.record(activity) } }
        share.onFileReceived = { [weak notifications] url, device in notifications?.announce(file: url, from: device) }
        start()
        clipboard.startWatching()
    }

    func requestPair(_ id: String) { connected[id]?.requestPair() }

    func accept(_ id: String) { connected[id]?.accept() }

    func reject(_ id: String) { connected[id]?.reject() }

    func unpair(_ id: String) { connected[id]?.unpair() }

    func ring(_ id: String) { connected[id]?.send(FindMyPhone.request()) }

    func media(_ id: String, _ player: String, _ action: MediaAction) {
        connected[id]?.send(MediaRequest.action(player, action).toPacket())
    }

    func seek(_ id: String, _ player: String, to position: Int64) {
        connected[id]?.send(MediaRequest.seek(player, to: position).toPacket())
    }

    // MARK: Calls

    func answerCall() {
        guard let call else { return }
        connected[call.deviceId]?.send(Call.answer())
    }

    func declineCall() {
        guard let call else { return }
        connected[call.deviceId]?.send(Call.decline())
        endCall()
    }

    func hangUp() {
        guard let call else { return }
        connected[call.deviceId]?.send(Call.hangUp())
        endCall()
    }

    /// Places a call on the paired phone.
    func dial(_ number: String, name: String?) {
        let number = number.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty, let phone = connected.all.first(where: \.isPaired), phone.send(Call.dial(number)) else { return }

        call = ActiveCall(deviceId: phone.id, deviceName: phone.name, number: number, name: name, phase: .dialing)
        callPanel.show(self)
    }

    private func handleCall(_ state: Call.State, deviceId: String, deviceName: String) {
        if state.ended {
            endCall()
            return
        }

        let photo = state.photo.flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:))
        switch state.event {
        case .ringing:
            call = ActiveCall(deviceId: deviceId, deviceName: deviceName, number: state.number, name: state.contactName, photo: photo, phase: .ringing)
            callPanel.show(self)
        case .talking:
            var current = call ?? ActiveCall(deviceId: deviceId, deviceName: deviceName, number: state.number, name: state.contactName, photo: photo, phase: .dialing)
            if case .talking = current.phase {} else { current.phase = .talking(since: Date()) }
            call = current
            callPanel.show(self)
        case .missed:
            endCall()
            if let device = connected[deviceId] {
                notifications.announceMissedCall(from: state.contactName ?? state.number, number: state.number, device: device)
            }
        }
    }

    private func endCall() {
        call = nil
        callPanel.hide()
    }

    func sendClipboard(to id: String) {
        guard let device = connected[id] else { return }

        if !clipboard.send(to: device) {
            record(Activity(.failed, title: "Clipboard is empty", detail: "Copy some text first"))
        }
    }

    /// Opens a file picker and sends what the user picks.
    func chooseFiles(for id: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Send"
        panel.message = "Choose files to send to your phone"
        panel.begin { [weak self] response in
            guard response == .OK else { return }

            let urls = panel.urls
            Task { @MainActor in self?.sendFiles(urls, to: id) }
        }
    }

    func sendFiles(_ urls: [URL], to id: String) {
        guard let device = connected[id] else { return }

        for url in urls {
            let started = Activity(.sending, title: url.lastPathComponent, detail: "Sending to \(device.name)")
            record(started)

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                Self.send(url, to: device) { error in
                    var done = started
                    done.date = Date()
                    done.kind = error == nil ? .sent : .failed
                    done.detail = error == nil ? "Sent to \(device.name)" : "Could not send to \(device.name)"

                    Task { @MainActor in self?.record(done) }
                }
            }
        }
    }

    func clearRecent() {
        recent.removeAll { !$0.isInProgress }
    }

    private func record(_ activity: Activity) {
        if let index = recent.firstIndex(where: { $0.id == activity.id }) {
            recent[index] = activity
            return
        }

        recent.insert(activity, at: 0)
        if recent.count > 20 { recent.removeLast(recent.count - 20) }
    }

    private func countNotification() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != notificationsDay {
            notificationsDay = today
            notificationsToday = 0
        }

        notificationsToday += 1
    }

    /// Offers one file to the phone. `completion` is called once, when it is done or failed.
    private nonisolated static func send(_ url: URL, to device: Device, completion: @escaping (Error?) -> Void) {
        let attributes: [FileAttributeKey: Any]
        let source: FileHandle
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            source = try FileHandle(forReadingFrom: url)
        } catch {
            completion(error)
            return
        }

        guard device.isPaired else {
            try? source.close()
            completion(ProtocolError("not paired"))
            return
        }

        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date).map { Int64($0.timeIntervalSince1970 * 1000) }
        let packet = Share.filePacket(name: url.lastPathComponent, size: size, lastModifiedMillis: modified)

        // On failure it calls completion itself.
        device.sendWithPayload(packet, size: size, source: source, completion: completion)
    }

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

        mediaPlugin.forget(device.id)

        log.info("Disconnected from \(device.name, privacy: .public): \(device.link.closeReason ?? "unknown", privacy: .public)")

        publish()
    }

    fileprivate func publish() {
        syncMessages()

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
                    code: showsCode ? device.verificationCode : nil,
                    battery: battery.status(for: device.id),
                    media: mediaPlugin.nowPlaying(for: device.id)
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// Texts come from the first paired phone.
    private func syncMessages() {
        let phone = connected.all.first { $0.isPaired }

        if let phone, messagesDevice != phone.id || !messages.hasPhone {
            messagesDevice = phone.id
            messages.attach(phone.id)
        } else if phone == nil, let id = messagesDevice {
            messages.detach(id)
        }
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
