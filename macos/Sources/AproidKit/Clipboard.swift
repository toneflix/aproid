import Foundation

/// A copied picture or file. `safeName` has no folders, so it can't be saved outside the target folder.
public struct ClipboardFile: Equatable, Sendable {
    public var name: String
    public var mimeType: String

    public init(name: String, mimeType: String) {
        self.name = name
        self.mimeType = mimeType
    }

    public var safeName: String { Share.safeName(name) }
}

/// Shared clipboard text ("kdeconnect.clipboard" and "kdeconnect.clipboard.connect"), and copied files
/// ("flyylink.clipboard.file"). Mirrors Clipboard.kt.
public enum Clipboard {
    /// Bigger copies are left alone, so copying a film in Finder doesn't start a long transfer.
    public static let fileLimit: Int64 = 50 * 1024 * 1024

    /// Announces a copied file. Send it with `Device.sendWithPayload`.
    public static func filePacket(name: String, mimeType: String) -> NetworkPacket {
        NetworkPacket(type: PacketType.clipboardFile, body: ["name": .string(name), "mimeType": .string(mimeType)])
    }

    public static func file(_ packet: NetworkPacket) -> ClipboardFile? {
        guard packet.type == PacketType.clipboardFile, packet.payloadSize != nil, let name = packet.string("name") else { return nil }

        return ClipboardFile(name: name, mimeType: packet.string("mimeType") ?? "application/octet-stream")
    }

    public static func packet(_ content: String) -> NetworkPacket {
        NetworkPacket(type: PacketType.clipboard, body: ["content": .string(content)])
    }

    /// Sent right after connecting, so the peer can tell whether it is newer than its own.
    public static func connectPacket(_ content: String, timestampMillis: Int64) -> NetworkPacket {
        NetworkPacket(type: PacketType.clipboardConnect, body: ["content": .string(content), "timestamp": .int(timestampMillis)])
    }

    /// The text in either clipboard packet, or nil.
    public static func content(_ packet: NetworkPacket) -> String? {
        guard packet.type == PacketType.clipboard || packet.type == PacketType.clipboardConnect,
              let content = packet.string("content"), !content.isEmpty
        else { return nil }

        return content
    }
}
