import Crypto
import _CryptoExtras
import Foundation

/// Finding the phone over Bluetooth when Wi-Fi discovery fails. The phone offers a Bluetooth LE
/// service; a paired Mac writes a `Request`, and the phone answers with where to reach it, and
/// optionally a hotspot to join, sealed to that Mac's certificate. Mirrors Nearby.kt. Only the
/// phone seals answers, so this side only opens them.
public enum Nearby {
    public static let service = "a9d2e4b0-6f1c-4e8a-b7d3-5c0f2a1e9b40"
    public static let request = "a9d2e4b0-6f1c-4e8a-b7d3-5c0f2a1e9b41"
    public static let answer = "a9d2e4b0-6f1c-4e8a-b7d3-5c0f2a1e9b42"

    public enum Want: String, Sendable {
        /// Just tell me your address.
        case connect
        /// We share no network: start a hotspot for me to join.
        case hotspot
    }

    public struct Request: Equatable, Sendable {
        public var deviceId: String
        public var want: Want

        public init(deviceId: String, want: Want) {
            self.deviceId = deviceId
            self.want = want
        }

        public init?(bytes: Data) {
            guard let json = try? JSONDecoder().decode([String: JSONValue].self, from: bytes),
                  let id = json["id"]?.stringValue, DeviceIdentity.isValidDeviceId(id),
                  let want = json["want"]?.stringValue.flatMap(Want.init(rawValue:))
            else { return nil }

            self.init(deviceId: id, want: want)
        }

        public func bytes() -> Data {
            let json: [String: JSONValue] = ["id": .string(deviceId), "want": .string(want.rawValue)]
            return (try? JSONEncoder().encode(json)) ?? Data()
        }
    }

    /// Where to reach the phone. `ssid` and `password` are set when it started a hotspot.
    public struct Answer: Equatable, Sendable {
        public var deviceId: String
        public var addresses: [String]
        public var port: UInt16
        public var ssid: String?
        public var password: String?

        public init(deviceId: String, addresses: [String], port: UInt16, ssid: String? = nil, password: String? = nil) {
            self.deviceId = deviceId
            self.addresses = addresses
            self.port = port
            self.ssid = ssid
            self.password = password
        }

        init?(json: [String: JSONValue]) {
            guard let id = json["i"]?.stringValue,
                  let port = json["p"]?.intValue, (1...65535).contains(port)
            else { return nil }

            self.init(
                deviceId: id,
                addresses: (json["a"]?.arrayValue ?? []).compactMap(\.stringValue),
                port: UInt16(port),
                ssid: json["s"]?.stringValue,
                password: json["k"]?.stringValue
            )
        }
    }

    private static let nonceSize = 12
    private static let tagSize = 16

    /// Reads an answer sealed to our key: an RSA-OAEP (SHA-256) wrapped AES-GCM key, the nonce, then the ciphertext.
    /// Throws when it isn't for our key or was changed on the way.
    public static func open(_ sealed: Data, privateKeyPEM: String) throws -> Answer {
        let bytes = [UInt8](sealed)
        guard bytes.count > 2 else { throw ProtocolError("answer too short") }

        let wrappedSize = Int(bytes[0]) << 8 | Int(bytes[1])
        let nonceStart = 2 + wrappedSize
        let sealedStart = nonceStart + nonceSize
        guard bytes.count >= sealedStart + tagSize else { throw ProtocolError("answer too short") }

        let privateKey = try _RSA.Encryption.PrivateKey(pemRepresentation: privateKeyPEM)
        let key = try privateKey.decrypt(Data(bytes[2..<nonceStart]), padding: .PKCS1_OAEP_SHA256)

        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: Data(bytes[nonceStart..<sealedStart])),
            ciphertext: Data(bytes[sealedStart..<(bytes.count - tagSize)]),
            tag: Data(bytes[(bytes.count - tagSize)...])
        )
        let plain = try AES.GCM.open(box, using: SymmetricKey(data: key))

        guard let answer = Answer(json: try JSONDecoder().decode([String: JSONValue].self, from: plain)) else {
            throw ProtocolError("answer is not valid")
        }
        return answer
    }
}
