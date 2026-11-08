import Crypto
import _CryptoExtras
import Foundation
import NIOSSL
import SwiftASN1
import X509

/// This device's self-signed certificate. The common name is the device id,
/// which is how KDE Connect ties a TLS session to an identity.
public final class DeviceCertificate {
    public let certificateDER: [UInt8]
    /// PEM private key, for storage.
    public let privateKeyPEM: String
    /// SubjectPublicKeyInfo bytes, used for the verification code.
    public let publicKeyDER: [UInt8]

    let nioCertificate: NIOSSLCertificate
    let nioPrivateKey: NIOSSLPrivateKey

    public init(certificateDER: [UInt8], privateKeyPEM: String) throws {
        self.certificateDER = certificateDER
        self.privateKeyPEM = privateKeyPEM

        nioCertificate = try NIOSSLCertificate(bytes: certificateDER, format: .der)
        nioPrivateKey = try NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem)
        publicKeyDER = try nioCertificate.extractPublicKey().toSPKIBytes()
    }

    public var deviceId: String? { Self.commonName(ofDER: certificateDER) }

    public static func generate(deviceId: String, now: Date = Date()) throws -> DeviceCertificate {
        let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let name = try DistinguishedName {
            CommonName(deviceId)
            OrganizationName("KDE")
            OrganizationalUnitName("KDE Connect")
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(key.publicKey),
            notValidBefore: now.addingTimeInterval(-86_400),
            notValidAfter: now.addingTimeInterval(3650 * 86_400),
            issuer: name,
            subject: name,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: Certificate.Extensions(),
            issuerPrivateKey: Certificate.PrivateKey(key)
        )
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)

        return try DeviceCertificate(certificateDER: serializer.serializedBytes, privateKeyPEM: key.pemRepresentation)
    }

    public static func commonName(ofDER der: [UInt8]) -> String? {
        guard let certificate = try? Certificate(derEncoded: der) else { return nil }

        for rdn in certificate.subject {
            for attribute in rdn where attribute.type == .RDNAttributeType.commonName {
                return String(describing: attribute.value)
            }
        }

        return nil
    }
}

/// The short code both screens show while pairing. It is a SHA-256 over both
/// public keys (larger first, compared as unsigned bytes) and the pair request
/// timestamp, cut to 8 hex characters. Mirrors VerificationKey.kt.
public enum VerificationKey {
    public static func compute(_ publicKeyA: [UInt8], _ publicKeyB: [UInt8], timestamp: Int64) -> String {
        let aFirst = !publicKeyA.lexicographicallyPrecedes(publicKeyB)
        let (first, second) = aFirst ? (publicKeyA, publicKeyB) : (publicKeyB, publicKeyA)

        var hasher = SHA256()
        hasher.update(data: first)
        hasher.update(data: second)
        hasher.update(data: Array(String(timestamp).utf8))
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()

        return String(hex.prefix(8)).uppercased()
    }
}
