import Foundation

public protocol DeviceDelegate: AnyObject {
    /// The peer asked to pair. Show `code` and call `accept()` or `reject()`.
    func devicePairRequested(_ device: Device, code: String)
    func device(_ device: Device, pairStateChanged state: PairState)
    func device(_ device: Device, received packet: NetworkPacket)
    func deviceDisconnected(_ device: Device)
}

public extension DeviceDelegate {
    func devicePairRequested(_ device: Device, code: String) {}
    func device(_ device: Device, pairStateChanged state: PairState) {}
    func device(_ device: Device, received packet: NetworkPacket) {}
    func deviceDisconnected(_ device: Device) {}
}

/// A connected peer: its encrypted link plus pairing. Packets from a device that
/// is not paired are dropped, except pairing packets. Mirrors Device.kt.
public final class Device {
    public let link: DeviceLink
    public weak var delegate: DeviceDelegate?

    private let ownCertificate: DeviceCertificate
    private let trustStore: TrustStore
    private let clock: () -> Int64
    private let pairing: PairingStateMachine
    private let lock = NSLock()

    public init(
        link: DeviceLink,
        ownCertificate: DeviceCertificate,
        trustStore: TrustStore,
        clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }
    ) {
        self.link = link
        self.ownCertificate = ownCertificate
        self.trustStore = trustStore
        self.clock = clock
        self.pairing = PairingStateMachine(state: trustStore.isTrusted(link.identity.deviceId) ? .paired : .notPaired)
    }

    public var id: String { link.identity.deviceId }

    public var name: String { link.identity.deviceName }

    public var pairState: PairState { lock.withLock { pairing.state } }

    public var isPaired: Bool { pairState == .paired }

    /// The code to show on screen while a pair request is open.
    public var verificationCode: String {
        let timestamp = lock.withLock { pairing.requestTimestamp }

        return VerificationKey.compute(ownCertificate.publicKeyDER, link.publicKeyDER, timestamp: timestamp)
    }

    public func start() {
        link.onPacket = { [weak self] packet in self?.handle(packet) }
        link.onClosed = { [weak self] in
            guard let self else { return }
            self.delegate?.deviceDisconnected(self)
        }
    }

    @discardableResult
    public func send(_ packet: NetworkPacket) -> Bool {
        guard isPaired else { return false }

        link.send(packet)

        return true
    }

    public func requestPair() { run { $0.requestPair(now: clock()) } }

    public func accept() { run { $0.accept() } }

    public func reject() { run { $0.reject() } }

    public func unpair() { run { $0.unpair() } }

    /// Call every few seconds so unanswered requests expire.
    public func tick() { run { $0.tick(now: clock()) } }

    private func handle(_ packet: NetworkPacket) {
        if packet.type == PacketType.pair {
            run { $0.handle(packet, now: clock()) }
            return
        }

        if isPaired { delegate?.device(self, received: packet) }
    }

    private func run(_ step: (PairingStateMachine) -> PairAction) {
        let (action, state) = lock.withLock { (step(pairing), pairing.state) }

        switch action {
        case .none:
            return
        case .askUser:
            delegate?.devicePairRequested(self, code: verificationCode)
        case .send(let packet):
            link.send(packet)
        case .paired, .unpaired:
            break
        }

        switch state {
        case .paired: trustStore.trust(id, certificate: link.certificateDER)
        case .notPaired: trustStore.forget(id)
        case .requested, .requestedByPeer: break
        }

        delegate?.device(self, pairStateChanged: state)
    }
}
