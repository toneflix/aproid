import XCTest
@testable import AproidKit

final class DeviceCertificateTests: XCTestCase {
    func testCommonNameIsDeviceId() throws {
        let id = DeviceIdentity.newDeviceId()

        let certificate = try DeviceCertificate.generate(deviceId: id)

        XCTAssertEqual(certificate.deviceId, id)
    }

    func testSurvivesStorage() throws {
        let certificate = try DeviceCertificate.generate(deviceId: DeviceIdentity.newDeviceId())

        let loaded = try DeviceCertificate(certificateDER: certificate.certificateDER, privateKeyPEM: certificate.privateKeyPEM)

        XCTAssertEqual(loaded.publicKeyDER, certificate.publicKeyDER)
    }

    func testVerificationKeyIsTheSameOnBothSides() throws {
        let a = try DeviceCertificate.generate(deviceId: DeviceIdentity.newDeviceId()).publicKeyDER
        let b = try DeviceCertificate.generate(deviceId: DeviceIdentity.newDeviceId()).publicKeyDER

        let code = VerificationKey.compute(a, b, timestamp: 1_700_000_000)

        XCTAssertEqual(code, VerificationKey.compute(b, a, timestamp: 1_700_000_000))
        XCTAssertEqual(code.count, 8)
        XCTAssertNotEqual(code, VerificationKey.compute(a, b, timestamp: 1_700_000_001))
    }

    /// Same inputs as the Kotlin side must give the same code.
    func testVerificationKeyMatchesKotlin() {
        XCTAssertEqual(VerificationKey.compute([1, 2, 3], [0xFF], timestamp: 42), VerificationKey.compute([0xFF], [1, 2, 3], timestamp: 42))
        XCTAssertEqual(VerificationKey.compute([1, 2, 3], [0xFF], timestamp: 42), "89CE2D9C")
    }
}

/// Collects links and device events so tests can wait on them.
final class Recorder: DeviceDelegate {
    let links = Queue<DeviceLink>()
    let requests = Queue<String>()
    let packets = Queue<NetworkPacket>()
    let paired = Queue<PairState>()
    let disconnected = Queue<Bool>()

    func devicePairRequested(_ device: Device, code: String) { requests.put(code) }

    func device(_ device: Device, pairStateChanged state: PairState) {
        if state == .paired { paired.put(state) }
    }

    func device(_ device: Device, received packet: NetworkPacket) { packets.put(packet) }

    func deviceDisconnected(_ device: Device) { disconnected.put(true) }
}

final class Queue<T> {
    private var items: [T] = []
    private let condition = NSCondition()

    func put(_ item: T) {
        condition.lock()
        items.append(item)
        condition.signal()
        condition.unlock()
    }

    func take(timeout: TimeInterval = 10) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }

        while items.isEmpty {
            if !condition.wait(until: deadline) { return nil }
        }

        return items.removeFirst()
    }
}

final class LanLinkTests: XCTestCase {
    private struct Peer {
        let identity: DeviceIdentity
        let certificate: DeviceCertificate
        let trust: InMemoryTrustStore
        let recorder: Recorder
        let connected: ConnectedSet
        let lan: LanLink

        init(name: String, type: DeviceType, ports: ClosedRange<UInt16>) throws {
            let identity = DeviceIdentity(deviceId: DeviceIdentity.newDeviceId(), deviceName: name, deviceType: type)
            let certificate = try DeviceCertificate.generate(deviceId: identity.deviceId)
            let trust = InMemoryTrustStore()
            let recorder = Recorder()
            let connected = ConnectedSet()

            self.identity = identity
            self.certificate = certificate
            self.trust = trust
            self.recorder = recorder
            self.connected = connected
            // High ports so the test does not clash with a real KDE Connect install.
            lan = try LanLink(
                identityProvider: { identity },
                certificate: certificate,
                trustStore: trust,
                udpPort: 41716,
                tcpPorts: ports,
                isConnected: { connected.contains($0) },
                onLink: { recorder.links.put($0) }
            )
        }
    }

    private var mac: Peer!
    private var phone: Peer!

    override func setUpWithError() throws {
        mac = try Peer(name: "Mac", type: .laptop, ports: 41716...41730)
        phone = try Peer(name: "Phone", type: .phone, ports: 41731...41764)
        try mac.lan.start()
    }

    override func tearDown() {
        mac.lan.stop()
    }

    private func connect() throws -> (onPhone: DeviceLink, onMac: DeviceLink) {
        var announced = mac.identity
        announced.tcpPort = mac.lan.tcpPort
        phone.lan.connect(to: announced, host: "127.0.0.1")

        let onPhone = try XCTUnwrap(phone.recorder.links.take())
        let onMac = try XCTUnwrap(mac.recorder.links.take())

        return (onPhone, onMac)
    }

    func testLinkIsEncryptedAndCarriesIdentities() throws {
        let (onPhone, onMac) = try connect()

        XCTAssertEqual(onPhone.identity.deviceId, mac.identity.deviceId)
        XCTAssertEqual(onMac.identity.deviceId, phone.identity.deviceId)
        XCTAssertEqual(DeviceCertificate.commonName(ofDER: onPhone.certificateDER), mac.identity.deviceId)
    }

    func testPairingShowsTheSameCodeAndTrustsBothSides() throws {
        let (onPhone, onMac) = try connect()
        let phoneDevice = Device(link: onPhone, ownCertificate: phone.certificate, trustStore: phone.trust)
        let macDevice = Device(link: onMac, ownCertificate: mac.certificate, trustStore: mac.trust)
        phoneDevice.delegate = phone.recorder
        macDevice.delegate = mac.recorder
        phoneDevice.start()
        macDevice.start()

        phoneDevice.requestPair()
        let codeOnMac = mac.recorder.requests.take()

        XCTAssertEqual(codeOnMac, phoneDevice.verificationCode)

        macDevice.accept()

        XCTAssertEqual(phone.recorder.paired.take(), .paired)
        XCTAssertTrue(phone.trust.isTrusted(mac.identity.deviceId))
        XCTAssertTrue(mac.trust.isTrusted(phone.identity.deviceId))

        XCTAssertTrue(phoneDevice.send(NetworkPacket(type: PacketType.ping)))
        XCTAssertEqual(mac.recorder.packets.take()?.type, PacketType.ping)
    }

    func testChangedCertificateIsRejected() throws {
        let other = try DeviceCertificate.generate(deviceId: phone.identity.deviceId)
        mac.trust.trust(phone.identity.deviceId, certificate: other.certificateDER)

        var announced = mac.identity
        announced.tcpPort = mac.lan.tcpPort
        phone.lan.connect(to: announced, host: "127.0.0.1")

        XCTAssertNil(mac.recorder.links.take(timeout: 3))
    }

    func testBothSidesKeepTheSameLinkWhenTheyConnectAtOnce() throws {
        try phone.lan.start()
        defer { phone.lan.stop() }

        var macAnnounced = mac.identity
        macAnnounced.tcpPort = mac.lan.tcpPort
        phone.lan.connect(to: macAnnounced, host: "127.0.0.1")
        let phoneOwn = try XCTUnwrap(phone.recorder.links.take())
        let macFromPhone = try XCTUnwrap(mac.recorder.links.take())

        var phoneAnnounced = phone.identity
        phoneAnnounced.tcpPort = phone.lan.tcpPort
        mac.lan.connect(to: phoneAnnounced, host: "127.0.0.1")
        let macOwn = try XCTUnwrap(mac.recorder.links.take())
        let phoneFromMac = try XCTUnwrap(phone.recorder.links.take())

        // The phone sees its own link first, the Mac sees its own first.
        let phoneKeepsItsOwn = DeviceLink.keepsExisting(phoneOwn, over: phoneFromMac, ownDeviceId: phone.identity.deviceId)
        let macKeepsItsOwn = DeviceLink.keepsExisting(macOwn, over: macFromPhone, ownDeviceId: mac.identity.deviceId)

        XCTAssertNotEqual(phoneKeepsItsOwn, macKeepsItsOwn)
    }

    func testReconnectReplacesTheOldLink() throws {
        let (first, _) = try connect()
        let (second, _) = try connect()

        XCTAssertFalse(DeviceLink.keepsExisting(first, over: second, ownDeviceId: phone.identity.deviceId))
    }

    func testHeartbeatIsAnswered() throws {
        let (onPhone, onMac) = try connect()
        let macDevice = Device(link: onMac, ownCertificate: mac.certificate, trustStore: mac.trust)
        macDevice.start()
        let received = Queue<NetworkPacket>()
        onPhone.onPacket = { received.put($0) }

        onPhone.send(NetworkPacket(type: PacketType.heartbeat, body: ["pong": .bool(false)]))

        let answer = received.take()
        XCTAssertEqual(answer?.type, PacketType.heartbeat)
        XCTAssertEqual(answer?.bool("pong"), true)
        withExtendedLifetime(macDevice) {}
    }

    func testSilentLinkIsClosed() throws {
        let (onPhone, _) = try connect()
        let clock = Clock()
        let device = Device(link: onPhone, ownCertificate: phone.certificate, trustStore: phone.trust, clock: { clock.now })
        device.delegate = phone.recorder
        device.start()

        clock.now += Device.heartbeatTimeoutSeconds + 1
        device.tick()

        XCTAssertEqual(phone.recorder.disconnected.take(), true)
        XCTAssertTrue(onPhone.closeReason?.contains("heartbeat") == true)
    }

    func testIdleLinkStaysOpen() throws {
        let (onPhone, onMac) = try connect()

        Thread.sleep(forTimeInterval: 11)

        XCTAssertTrue(onPhone.isOpen)
        XCTAssertTrue(onMac.isOpen)
    }

    func testFileTravelsOverItsOwnTlsConnection() throws {
        let (onPhone, onMac) = try connect()
        phone.trust.trust(mac.identity.deviceId, certificate: onPhone.certificateDER)
        mac.trust.trust(phone.identity.deviceId, certificate: onMac.certificateDER)
        let phoneDevice = Device(link: onPhone, ownCertificate: phone.certificate, trustStore: phone.trust)
        let macDevice = Device(link: onMac, ownCertificate: mac.certificate, trustStore: mac.trust)
        macDevice.delegate = mac.recorder
        phoneDevice.start()
        macDevice.start()

        let bytes = Data((0..<300_000).map { UInt8($0 % 251) })
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sourceURL = folder.appendingPathComponent("photo.jpg")
        let sinkURL = folder.appendingPathComponent("received.jpg")
        try bytes.write(to: sourceURL)
        FileManager.default.createFile(atPath: sinkURL.path, contents: nil)

        let sent = phoneDevice.sendWithPayload(
            Share.filePacket(name: "photo.jpg", size: Int64(bytes.count)),
            size: Int64(bytes.count),
            source: try FileHandle(forReadingFrom: sourceURL)
        )
        let packet = try XCTUnwrap(mac.recorder.packets.take())
        let sink = try FileHandle(forWritingTo: sinkURL)
        try macDevice.receivePayload(packet, into: sink).wait()
        try sink.close()

        XCTAssertTrue(sent)
        XCTAssertEqual(Share(packet: packet), .file(name: "photo.jpg", size: Int64(bytes.count)))
        XCTAssertEqual(try Data(contentsOf: sinkURL), bytes)
    }

    func testAnnouncementConnectsToANewPeer() throws {
        var announced = mac.identity
        announced.tcpPort = mac.lan.tcpPort

        XCTAssertTrue(phone.lan.handleAnnouncement(announced, host: "127.0.0.1"))
        XCTAssertEqual(mac.recorder.links.take()?.identity.deviceId, phone.identity.deviceId)
    }

    func testAnnouncementKeepsTheExistingLink() throws {
        var announced = mac.identity
        announced.tcpPort = mac.lan.tcpPort
        phone.connected.insert(mac.identity.deviceId)

        XCTAssertFalse(phone.lan.handleAnnouncement(announced, host: "127.0.0.1"))
        XCTAssertNil(mac.recorder.links.take(timeout: 2))
    }
}

/// Device ids a test peer treats as already connected.
private final class ConnectedSet: @unchecked Sendable {
    private var ids: Set<String> = []
    private let lock = NSLock()

    func insert(_ id: String) {
        lock.withLock { _ = ids.insert(id) }
    }

    func contains(_ id: String) -> Bool {
        lock.withLock { ids.contains(id) }
    }
}

/// A clock tests can move forward.
private final class Clock: @unchecked Sendable {
    var now: Int64 = 1_000
}
