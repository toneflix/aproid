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

    func devicePairRequested(_ device: Device, code: String) { requests.put(code) }

    func device(_ device: Device, pairStateChanged state: PairState) {
        if state == .paired { paired.put(state) }
    }

    func device(_ device: Device, received packet: NetworkPacket) { packets.put(packet) }
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
        let lan: LanLink

        init(name: String, type: DeviceType, ports: ClosedRange<UInt16>) throws {
            let identity = DeviceIdentity(deviceId: DeviceIdentity.newDeviceId(), deviceName: name, deviceType: type)
            let certificate = try DeviceCertificate.generate(deviceId: identity.deviceId)
            let trust = InMemoryTrustStore()
            let recorder = Recorder()

            self.identity = identity
            self.certificate = certificate
            self.trust = trust
            self.recorder = recorder
            // High ports so the test does not clash with a real KDE Connect install.
            lan = try LanLink(
                identityProvider: { identity },
                certificate: certificate,
                trustStore: trust,
                udpPort: 41716,
                tcpPorts: ports,
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
}
