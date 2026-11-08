import Foundation
import NIOCore

/// An encrypted connection to one peer. Callbacks run on a networking thread.
public final class DeviceLink {
    public let identity: DeviceIdentity
    public let certificateDER: [UInt8]
    public let publicKeyDER: [UInt8]
    public let host: String
    /// True when we opened the TCP connection.
    public let isOutgoing: Bool
    public let openedAt = Date()

    public var onPacket: ((NetworkPacket) -> Void)?
    public var onClosed: (() -> Void)?

    private let channel: Channel

    init(identity: DeviceIdentity, certificateDER: [UInt8], publicKeyDER: [UInt8], host: String, isOutgoing: Bool, channel: Channel) {
        self.identity = identity
        self.certificateDER = certificateDER
        self.publicKeyDER = publicKeyDER
        self.host = host
        self.isOutgoing = isOutgoing
        self.channel = channel
    }

    /// Links opened this close together are two sides connecting at the same moment.
    public static let raceWindow: TimeInterval = 3

    /// Who opened the TCP connection: us or the peer.
    public func openerId(ownDeviceId: String) -> String {
        isOutgoing ? ownDeviceId : identity.deviceId
    }

    /// Decides which link to keep when a second one to the same device arrives.
    ///
    /// If both sides connected at the same moment, both must keep the same TCP connection,
    /// so the one opened by the device with the larger id wins. Otherwise the new link wins,
    /// because a peer only reconnects when its old link has died. Mirrors DeviceLink.kt.
    public static func keepsExisting(_ existing: DeviceLink, over new: DeviceLink, ownDeviceId: String) -> Bool {
        guard existing.isOpen, abs(new.openedAt.timeIntervalSince(existing.openedAt)) <= raceWindow else { return false }

        return existing.openerId(ownDeviceId: ownDeviceId) > new.openerId(ownDeviceId: ownDeviceId)
    }

    public var isOpen: Bool { channel.isActive }

    public func send(_ packet: NetworkPacket) {
        guard let data = try? packet.serialize() else { return }

        let buffer = channel.allocator.buffer(bytes: data)
        channel.writeAndFlush(buffer, promise: nil)
    }

    public func close() {
        channel.close(promise: nil)
    }

    func deliver(_ packet: NetworkPacket) {
        onPacket?(packet)
    }

    func closed() {
        onClosed?()
    }
}
