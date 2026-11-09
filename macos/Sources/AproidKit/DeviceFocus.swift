import Foundation

/// Picks the device that single-device features (the main screen, messages, photos, call audio) are about
/// while several paired devices stay connected at once. Mirrors DeviceFocus.kt.
public struct DeviceFocus: Sendable {
    public let preferredId: String?

    public init(preferredId: String?) {
        self.preferredId = preferredId
    }

    /// The preferred device when it is among `devices`, otherwise the first by name, then id.
    public func pick<T>(_ devices: [T], id: (T) -> String, name: (T) -> String) -> T? {
        if let preferred = devices.first(where: { id($0) == preferredId }) { return preferred }

        return devices.min { (name($0), id($0)) < (name($1), id($1)) }
    }
}
