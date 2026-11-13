import AppKit
import IOBluetooth
import OSLog
import FlyyLinkKit

/// Makes this Mac a Bluetooth hands-free device for the phone, like a car kit, so calls are heard and answered here.
/// Android sends call audio to a connected hands-free device by itself; FlyyLink only pairs, connects and steers it.
@MainActor
final class HandsFreeAudio: NSObject, ObservableObject {
    enum Stage: Equatable {
        case noPhone
        case checking
        case macOff
        case phoneOff
        case notAllowed
        case notPaired
        case pairing
        case paused
        case connecting
        case ready
        case failed(String)

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    @Published private(set) var stage = Stage.noPhone
    @Published private(set) var audioOnMac = false
    /// The phone's Bluetooth name, once it has reported it.
    @Published private(set) var phoneName: String?

    /// Whether calls should come to this Mac. Off keeps the phone paired but disconnected.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                retry()
            } else {
                disconnect()
                update()
            }
        }
    }

    var isReady: Bool { stage == .ready }

    /// Whether calls on this phone are heard and answered on this Mac.
    func carries(_ deviceId: String) -> Bool {
        isReady && phoneId == deviceId
    }

    /// The phone reports this Mac among its paired Bluetooth devices.
    var isPaired: Bool { status?.paired == true }

    /// Bluetooth's own name for this Mac, which the phone shows when pairing.
    var macName: String { IOBluetoothHostController.default()?.nameAsString() ?? Host.current().localizedName ?? "this Mac" }

    /// Sends a packet to the phone over the network. False when it isn't connected.
    var send: ((NetworkPacket) -> Bool)?

    private static let enabledKey = "callAudioEnabled"
    /// The phone whose calls this Mac carries.
    private(set) var phoneId: String?
    private var isOnline = false
    private var status: CallAudio.Status?
    private var handsFree: IOBluetoothHandsFreeDevice?
    private var isLinked = false
    /// Set when connecting failed, so it isn't retried until the user asks.
    private var gaveUp = false
    private var deadline: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private let log = Logger(subsystem: "com.toneflix.flyylink", category: "call-audio")

    override init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        super.init()
    }

    /// Follows the primary phone. A phone that drops off the network keeps its Bluetooth link.
    func attach(_ phoneId: String?) {
        defer { isOnline = phoneId != nil }
        guard let phoneId, !(isOnline && phoneId == self.phoneId) else { return }

        if phoneId != self.phoneId {
            disconnect()
            self.phoneId = phoneId
            status = nil
            phoneName = nil
            stage = .checking
        }

        refresh()
    }

    /// Asks the phone how its side of the link stands. It answers with `received(_:)`.
    func refresh() {
        guard phoneId != nil else { return }
        guard let address = macAddress else {
            stage = .macOff
            return
        }

        _ = send?(CallAudio.request(CallAudio.Request(.status, address: address, name: macName)))
    }

    func received(_ status: CallAudio.Status, from deviceId: String) {
        guard deviceId == phoneId else { return }

        self.status = status
        phoneName = status.name
        update()
    }

    /// Asks the phone to pair, and opens Bluetooth settings so this Mac can be found. Both screens then show a code.
    func pair() {
        guard let address = macAddress else {
            stage = .macOff
            return
        }

        stage = .pairing
        _ = send?(CallAudio.request(CallAudio.Request(.pair, address: address, name: macName)))
        openBluetoothSettings()
        expire(after: 90, "Pairing didn't finish. Pick \(macName) in your phone's Bluetooth settings.")
    }

    func retry() {
        if case .failed = stage { stage = .checking }

        gaveUp = false
        reconnect?.cancel()
        update()
        refresh()
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }

        NSWorkspace.shared.open(url)
    }

    // MARK: Calls

    /// Answers over Bluetooth, which brings the audio to this Mac. False when the link isn't up.
    func answer() -> Bool {
        guard isLinked, let handsFree else { return false }

        handsFree.acceptCall()
        return true
    }

    func moveAudio(toMac: Bool) {
        guard isLinked, let handsFree else { return }

        if toMac {
            handsFree.transferAudioToComputer()
        } else {
            handsFree.transferAudioToPhone()
        }
    }

    /// Mutes this Mac's microphone in the call.
    func setMuted(_ muted: Bool) {
        handsFree?.isInputMuted = muted
    }

    // MARK: Link

    private var macAddress: String? {
        CallAudio.normalizeAddress(IOBluetoothHostController.default()?.addressAsString())
    }

    private func update() {
        guard phoneId != nil else {
            stage = .noPhone
            return
        }
        guard macAddress != nil else {
            stage = .macOff
            return
        }
        if isLinked {
            stage = .ready
            return
        }
        guard let status else {
            stage = .checking
            return
        }

        if !status.bluetoothOn {
            stage = .phoneOff
        } else if !status.allowed {
            stage = .notAllowed
        } else if !status.paired {
            if stage != .pairing, !stage.isFailure { stage = .notPaired }
        } else if !isEnabled {
            stage = .paused
        } else if gaveUp {
            return
        } else if handsFree == nil {
            connect()
        }
    }

    private func connect() {
        guard let device = phoneDevice() else {
            gaveUp = true
            stage = .failed("Phone not found in Bluetooth devices. Remove it in Bluetooth settings and pair again.")
            return
        }

        log.info("Connecting hands-free to \(device.nameOrAddress ?? "phone", privacy: .public)")
        let handsFree: IOBluetoothHandsFreeDevice? = IOBluetoothHandsFreeDevice(device: device, delegate: self)
        self.handsFree = handsFree
        stage = .connecting
        handsFree?.connect()
        expire(after: 20, "Your phone refused. Turn on Calls for \(macName) in its Bluetooth settings.")
    }

    private func disconnect() {
        deadline?.cancel()
        reconnect?.cancel()
        handsFree?.disconnect()
        handsFree = nil
        isLinked = false
        audioOnMac = false
    }

    /// The paired phone in this Mac's Bluetooth list: the one used before, then one named like the phone, then the only phone.
    private func phoneDevice() -> IOBluetoothDevice? {
        let paired = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
        let key = "callAudioDevice.\(phoneId ?? "")"

        if let saved = UserDefaults.standard.string(forKey: key),
           let device = paired.first(where: { CallAudio.normalizeAddress($0.addressString) == saved }) {
            return device
        }

        let phones = paired.filter { Int($0.deviceClassMajor) == Int(kBluetoothDeviceClassMajorPhone) }
        let named = phoneName.flatMap { name in paired.first { $0.name == name } }
        guard let device = named ?? (phones.count == 1 ? phones.first : nil) else { return nil }

        UserDefaults.standard.set(CallAudio.normalizeAddress(device.addressString), forKey: key)
        return device
    }

    /// Fails the current step if it hasn't moved on in time.
    private func expire(after seconds: UInt64, _ reason: String) {
        let waiting = stage
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled, let self, self.stage == waiting else { return }

            if waiting == .connecting {
                self.disconnect()
                self.gaveUp = true
            }
            self.stage = .failed(reason)
        }
    }

    private func linked(_ ok: Bool) {
        deadline?.cancel()
        guard ok else {
            disconnect()
            gaveUp = true
            stage = .failed("Your phone refused. Restart Bluetooth on it and try again.")
            return
        }

        log.info("Hands-free link is up")
        isLinked = true
        update()
    }

    private func unlinked() {
        log.info("Hands-free link closed")
        let wasLinked = isLinked
        disconnect()
        update()

        // The phone went out of range or Bluetooth restarted: try again a little later.
        guard wasLinked, isEnabled else { return }
        reconnect = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }

            self?.retry()
        }
    }
}

extension HandsFreeAudio: IOBluetoothHandsFreeDeviceDelegate {
    @objc(handsFree:connected:)
    nonisolated func handsFree(_ device: IOBluetoothHandsFree!, connected status: NSNumber!) {
        let ok = status?.intValue == Int(kIOReturnSuccess)
        Task { @MainActor in self.linked(ok) }
    }

    @objc(handsFree:disconnected:)
    nonisolated func handsFree(_ device: IOBluetoothHandsFree!, disconnected status: NSNumber!) {
        Task { @MainActor in self.unlinked() }
    }

    @objc(handsFree:scoConnectionOpened:)
    nonisolated func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionOpened status: NSNumber!) {
        let ok = status?.intValue == Int(kIOReturnSuccess)
        Task { @MainActor in self.audioOnMac = ok }
    }

    @objc(handsFree:scoConnectionClosed:)
    nonisolated func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionClosed status: NSNumber!) {
        Task { @MainActor in self.audioOnMac = false }
    }
}

/// Hears the phone's reports about its side of the call audio link ("flyylink.callaudio").
final class CallAudioPlugin: Plugin {
    let incoming: Set<String> = [PacketType.callAudio]

    /// Called on any thread with each report.
    var onStatus: ((CallAudio.Status, String) -> Void)?

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let status = CallAudio.status(packet) else { return }

        onStatus?(status, device.id)
    }
}
