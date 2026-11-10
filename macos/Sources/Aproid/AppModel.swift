import AppKit
import Combine
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
    let location: PhoneLocation?
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

    /// The paired phone the panel, Messages, Photos, call audio and the Share menu use. Every paired phone stays connected.
    @Published private(set) var primaryId: String?

    /// The phone the user picked when several are paired. Kept across launches.
    var selectedPhone: String? {
        get { UserDefaults.standard.string(forKey: "selectedPhone") }
        set {
            UserDefaults.standard.set(newValue, forKey: "selectedPhone")
            publish()
        }
    }

    /// A paired phone is in Bluetooth range but not reachable over the network.
    @Published private(set) var phoneNearby = false
    /// What joining the phone's hotspot is doing, or why it failed.
    @Published private(set) var hotspotStatus: String?

    /// The phone being looked for: its map shows in the panel until closed.
    @Published var finding: String?
    @Published var mirrorsNotifications: Bool {
        didSet {
            notifications.isEnabled = mirrorsNotifications
            UserDefaults.standard.set(mirrorsNotifications, forKey: "mirrorsNotifications")
        }
    }

    /// How the panel switches between several paired phones.
    @Published var switcherStyle: PhoneSwitcherStyle {
        didSet { UserDefaults.standard.set(switcherStyle.rawValue, forKey: "switcherStyle") }
    }

    /// Sends what is shared from the Share menu.
    private(set) lazy var shareInbox = ShareInbox(model: self)

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
    private let locations = LocationPlugin()
    private let photosPlugin = PhotosPlugin()
    private let calls = CallPlugin()
    private let callAudioPlugin = CallAudioPlugin()
    /// Carries call audio over Bluetooth, with this Mac as the phone's hands-free device.
    let callAudio = HandsFreeAudio()
    private let callPanel = CallPanel()
    private var messagesDevice: String?
    private var photosDevice: String?

    let messages = MessagesStore()
    let photos = PhotosStore()
    let screen: ScreenMirror
    private let screenPlugin: ScreenPlugin
    private let screenWindow: ScreenWindowController
    private var screenSize: AnyCancellable?
    private let nearby: NearbyFinder
    private let hotspot = PhoneHotspot()
    private var lastNearbySearch = Date.distantPast
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
        nearby = NearbyFinder(ownId: identity.deviceId)
        let screen = ScreenMirror()
        self.screen = screen
        screenPlugin = ScreenPlugin(decoder: screen.decoder, audio: screen.audio)
        screenWindow = ScreenWindowController(mirror: screen)
        notifications = NotificationPlugin(devices: connected)
        plugins = PluginRouter([notifications, battery, clipboard, share, mediaPlugin, sms, calls, callAudioPlugin, locations, photosPlugin, screenPlugin])
        mirrorsNotifications = UserDefaults.standard.object(forKey: "mirrorsNotifications") as? Bool ?? true
        switcherStyle = UserDefaults.standard.string(forKey: "switcherStyle").flatMap(PhoneSwitcherStyle.init(rawValue:)) ?? .carousel
        notifications.isEnabled = mirrorsNotifications

        battery.onChange = { [weak self] in Task { @MainActor in self?.publish() } }
        mediaPlugin.onChange = { [weak self] in Task { @MainActor in self?.publish() } }
        locations.onChange = { [weak self] in Task { @MainActor in self?.publish() } }
        sms.onMessages = { [weak self] messages, deviceId in Task { @MainActor in self?.messages.ingest(messages, from: deviceId) } }
        calls.onState = { [weak self] state, device in
            let deviceId = device.id
            let deviceName = device.name
            Task { @MainActor in self?.handleCall(state, deviceId: deviceId, deviceName: deviceName) }
        }
        callAudioPlugin.onStatus = { [weak self] status, deviceId in Task { @MainActor in self?.callAudio.received(status, from: deviceId) } }
        callAudio.send = { [weak self] packet in
            guard let id = self?.callAudio.phoneId, let device = self?.connected[id] else { return false }
            return device.send(packet)
        }
        nearby.onNearby = { [weak self] found in Task { @MainActor in self?.nearbyChanged(found) } }
        nearby.onAnswer = { [weak self] answer in Task { @MainActor in self?.reach(answer) } }
        screen.send = { [weak self] id, packet in self?.connected[id]?.send(packet) ?? false }
        screenPlugin.onStarted = { [weak self] device in
            let deviceId = device.id
            let deviceName = device.name
            Task { @MainActor in
                self?.screen.started(deviceId: deviceId, name: deviceName)
                self?.screenWindow.show()
            }
        }
        screenPlugin.onEnded = { [weak self] deviceId in Task { @MainActor in self?.screen.ended(deviceId: deviceId) } }
        screenSize = screen.$videoSize.sink { [weak self] size in Task { @MainActor in self?.screenWindow.fit(size) } }
        photosPlugin.onPage = { [weak self] page, deviceId in Task { @MainActor in self?.photos.ingest(page, from: deviceId) } }
        photosPlugin.onPreview = { [weak self] id, url, deviceId in
            Task { @MainActor in self?.photos.ingestPreview(id, url: url, from: deviceId) }
        }
        photos.send = { [weak self] packet in
            guard let id = self?.primaryId, let device = self?.connected[id] else { return false }
            return device.send(packet)
        }
        messages.send = { [weak self] packet in
            guard let id = self?.messagesDevice, let device = self?.connected[id] else { return false }
            return device.send(packet)
        }
        clipboard.onSync = { [weak self] in Task { @MainActor in self?.clipboardSyncedAt = Date() } }
        notifications.onShown = { [weak self] in Task { @MainActor in self?.countNotification() } }
        share.onActivity = { [weak self] activity in Task { @MainActor in self?.record(activity) } }
        share.onFileReceived = { [weak notifications] url, device in notifications?.announce(file: url, from: device) }
        share.restore()
        start()
        clipboard.startWatching()
    }

    /// The paired phone after the one shown, wrapping round to the first.
    var nextPhone: DeviceState? {
        DeviceFocus(preferredId: primaryId).next(devices.filter { $0.pairState == .paired }, id: \.id, name: \.name)
    }

    func showNextPhone() {
        guard let next = nextPhone, next.id != primaryId else { return }

        selectedPhone = next.id
    }

    func requestPair(_ id: String) { connected[id]?.requestPair() }

    func accept(_ id: String) { connected[id]?.accept() }

    func reject(_ id: String) { connected[id]?.reject() }

    func unpair(_ id: String) { connected[id]?.unpair() }

    /// Rings the phone and asks where it is, so it can be found by sound or on the map.
    func ring(_ id: String) {
        guard let device = connected[id] else { return }

        device.send(FindMyPhone.request())
        locations.request(from: device)
        finding = id
    }

    /// Asks the phone to share its screen and opens the window that shows it.
    func mirror(_ id: String) {
        guard let device = connected[id], device.isPaired else { return }

        screen.begin(deviceId: id, name: device.name)
        screenWindow.show()
    }

    func media(_ id: String, _ player: String, _ action: MediaAction) {
        connected[id]?.send(MediaRequest.action(player, action).toPacket())
    }

    func seek(_ id: String, _ player: String, to position: Int64) {
        connected[id]?.send(MediaRequest.seek(player, to: position).toPacket())
    }

    // MARK: Calls

    /// Answers over Bluetooth when call audio is set up, so the call is heard here. Otherwise the phone answers.
    func answerCall() {
        guard let call else { return }
        if callAudio.carries(call.deviceId), callAudio.answer() { return }

        connected[call.deviceId]?.send(Call.answer())
    }

    /// Mutes the microphone the call is using: this Mac's when the audio is here, the phone's otherwise.
    func toggleMute() {
        guard var call else { return }

        call.isMuted.toggle()
        if callAudio.audioOnMac && callAudio.carries(call.deviceId) {
            callAudio.setMuted(call.isMuted)
        } else {
            connected[call.deviceId]?.send(Call.mute(call.isMuted))
        }
        self.call = call
    }

    /// Moves the call's audio between this Mac and the phone.
    func switchCallAudio() {
        callAudio.moveAudio(toMac: !callAudio.audioOnMac)
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
        guard !number.isEmpty, let phone = primaryPhone, phone.send(Call.dial(number)) else { return }

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
        if call?.isMuted == true {
            callAudio.setMuted(false)
            if let call { connected[call.deviceId]?.send(Call.mute(false)) }
        }

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

        let share = share
        DispatchQueue.global(qos: .userInitiated).async {
            urls.forEach { share.send($0, to: device) }
        }
    }

    /// Sends a web link to open on the phone, or other text to put on its clipboard.
    func sendText(_ text: String, to id: String) {
        guard let device = connected[id] else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmed).flatMap { ["http", "https"].contains($0.scheme?.lowercased()) ? $0 : nil }
        let packet = url.map { Share.linkPacket($0.absoluteString) } ?? Share.textPacket(trimmed)
        guard device.send(packet) else { return }

        if let url {
            record(Activity(.link(url), title: url.host ?? trimmed, detail: "Opened on \(device.name)"))
        } else {
            record(Activity(.text, title: "“\(trimmed.prefix(60))”", detail: "Copied to \(device.name)"))
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

                await self?.started(link, certificate: certificate)
            } catch {
                await self?.failed("Could not start: \(error)")
            }
        }
    }

    private func started(_ link: LanLink, certificate: DeviceCertificate) {
        self.link = link
        nearby.use(privateKeyPEM: certificate.privateKeyPEM)
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            link.broadcastIdentity()
            Task { @MainActor in
                self?.connected.all.forEach { $0.tick() }
                self?.searchNearbyIfLost()
            }
        }
        // Common modes keep it running while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        link.broadcastIdentity()
    }

    // MARK: Bluetooth fallback

    /// When no paired phone has answered on the network, look for one over Bluetooth now and then.
    private func searchNearbyIfLost() {
        let hasPhone = connected.all.contains { $0.isPaired }
        guard !hasPhone, !trustStore.trustedIds.isEmpty, Date().timeIntervalSince(lastNearbySearch) > 45 else { return }

        lastNearbySearch = Date()
        nearby.search(.connect)
    }

    private func nearbyChanged(_ found: Bool) {
        let hasPhone = connected.all.contains { $0.isPaired }
        phoneNearby = found && !hasPhone
    }

    /// The name of the phone's hotspot, once this Mac has been on it.
    var phoneHotspotName: String? { hotspotPhoneId.flatMap(hotspot.name(of:)) }

    private var hotspotPhoneId: String? {
        let candidates = [selectedPhone].compactMap { $0 } + trustStore.trustedIds
        return candidates.first { hotspot.name(of: $0) != nil }
    }

    /// Asks the phone to turn its hotspot on, then joins it when it shows up. This Mac leaves its current Wi-Fi.
    func joinPhoneHotspot() {
        lastNearbySearch = Date()
        nearby.search(.hotspot)

        guard let id = hotspotPhoneId else {
            hotspotStatus = "Turn on the hotspot on your phone, then pick it in the Wi-Fi menu. Aproid remembers it for next time."
            return
        }

        hotspotStatus = "Asking your phone to turn on its hotspot…"
        hotspot.join(deviceId: id) { [weak self] status in Task { @MainActor in self?.hotspotChanged(status) } }
    }

    func cancelHotspot() {
        hotspot.cancel()
        hotspotStatus = nil
    }

    private func hotspotChanged(_ status: PhoneHotspot.Status?) {
        switch status {
        case .waiting(let ssid): hotspotStatus = "Waiting for \(ssid). Tap the notification on your phone to turn it on."
        case .joining(let ssid): hotspotStatus = "Joining \(ssid)…"
        case .failed(let reason): hotspotStatus = reason
        case nil: hotspotStatus = "Joined. Connecting to your phone…"
        }
    }

    /// Remembers the phone's hotspot when this Mac is on it. Reading the Wi-Fi name needs location access.
    private func learnHotspot(_ device: Device) {
        let deviceId = device.id
        let host = device.link.host
        let hotspot = hotspot
        let nearby = nearby

        DispatchQueue.global(qos: .utility).async {
            if !hotspot.learn(deviceId: deviceId, phoneHost: host) { nearby.askForLocation() }
        }
    }

    /// Connects to the addresses the phone gave over Bluetooth.
    private func reach(_ answer: Nearby.Answer) {
        let peer = DeviceIdentity(deviceId: answer.deviceId, deviceName: "Phone", deviceType: .phone, tcpPort: answer.port)
        guard let link else { return }

        answer.addresses.forEach { _ = link.connect(to: peer, host: $0) }
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
        if device.isPaired {
            plugins.onPaired(device)
            phoneNearby = false
            hotspotStatus = nil
            hotspot.cancel()
            learnHotspot(device)
        }

        publish()
    }

    fileprivate func remove(_ device: Device) {
        guard connected.remove(device) else { return }

        mediaPlugin.forget(device.id)
        screen.ended(deviceId: device.id)

        log.info("Disconnected from \(device.name, privacy: .public): \(device.link.closeReason ?? "unknown", privacy: .public)")

        publish()
    }

    fileprivate func publish() {
        primaryId = primaryPhone?.id
        callAudio.attach(callAudioPhoneId)
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
                    media: mediaPlugin.nowPlaying(for: device.id),
                    location: locations.location(for: device.id)
                )
            }
            .sorted { $0.name < $1.name }
    }

    private var primaryPhone: Device? {
        DeviceFocus(preferredId: selectedPhone).pick(connected.all.filter(\.isPaired), id: \.id, name: \.name)
    }

    /// Call audio stays with its phone while that phone is connected, so switching phones keeps the Bluetooth link.
    private var callAudioPhoneId: String? {
        if let id = callAudio.phoneId, connected[id]?.isPaired == true { return id }

        return primaryId
    }

    /// Texts and photos come from the primary phone.
    private func syncMessages() {
        let phone = primaryPhone

        if let phone {
            photos.attach(phone.id)
            photosDevice = phone.id
        } else if let id = photosDevice {
            photos.detach(id)
        }

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
