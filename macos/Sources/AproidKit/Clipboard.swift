import Foundation

/// Shared clipboard text ("kdeconnect.clipboard" and "kdeconnect.clipboard.connect"). Mirrors Clipboard.kt.
public enum Clipboard {
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
