import Foundation
import NIOCore

/// An encrypted connection to one peer. Callbacks run on a networking thread.
public final class DeviceLink {
    public let identity: DeviceIdentity
    public let certificateDER: [UInt8]
    public let publicKeyDER: [UInt8]
    public let host: String

    public var onPacket: ((NetworkPacket) -> Void)?
    public var onClosed: (() -> Void)?

    private let channel: Channel

    init(identity: DeviceIdentity, certificateDER: [UInt8], publicKeyDER: [UInt8], host: String, channel: Channel) {
        self.identity = identity
        self.certificateDER = certificateDER
        self.publicKeyDER = publicKeyDER
        self.host = host
        self.channel = channel
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
