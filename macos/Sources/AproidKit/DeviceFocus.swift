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

    /// The device after the preferred one, by name then id, wrapping round to the first.
    public func next<T>(_ devices: [T], id: (T) -> String, name: (T) -> String) -> T? {
        let ordered = devices.sorted { (name($0), id($0)) < (name($1), id($1)) }
        guard !ordered.isEmpty else { return nil }

        let index = ordered.firstIndex { id($0) == preferredId } ?? -1
        return ordered[(index + 1) % ordered.count]
    }
}
