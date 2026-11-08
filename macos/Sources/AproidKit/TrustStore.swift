import Foundation

/// Certificates of paired devices, by device id.
public protocol TrustStore: AnyObject {
    func certificate(for deviceId: String) -> [UInt8]?
    func trust(_ deviceId: String, certificate: [UInt8])
    func forget(_ deviceId: String)
}

public extension TrustStore {
    func isTrusted(_ deviceId: String) -> Bool { certificate(for: deviceId) != nil }
}

public final class InMemoryTrustStore: TrustStore {
    private var certificates: [String: [UInt8]] = [:]
    private let lock = NSLock()

    public init() {}

    public func certificate(for deviceId: String) -> [UInt8]? {
        lock.withLock { certificates[deviceId] }
    }

    public func trust(_ deviceId: String, certificate: [UInt8]) {
        lock.withLock { certificates[deviceId] = certificate }
    }

    public func forget(_ deviceId: String) {
        lock.withLock { _ = certificates.removeValue(forKey: deviceId) }
    }
}

/// Keeps trusted certificates in UserDefaults.
public final class DefaultsTrustStore: TrustStore {
    private let defaults: UserDefaults
    private let key = "trustedCertificates"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func certificate(for deviceId: String) -> [UInt8]? {
        (defaults.dictionary(forKey: key)?[deviceId] as? Data).map { Array($0) }
    }

    public func trust(_ deviceId: String, certificate: [UInt8]) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        all[deviceId] = Data(certificate)
        defaults.set(all, forKey: key)
    }

    public func forget(_ deviceId: String) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        all.removeValue(forKey: deviceId)
        defaults.set(all, forKey: key)
    }
}
