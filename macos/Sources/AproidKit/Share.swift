import Foundation

/// What a "kdeconnect.share.request" carries: a file, a link or some text. Mirrors Share.kt.
public enum Share: Equatable, Sendable {
    case file(name: String, size: Int64)
    case link(String)
    case text(String)

    /// The packet announcing a file. Send it with `Device.sendWithPayload`, which adds the payload.
    public static func filePacket(name: String, size: Int64, lastModifiedMillis: Int64? = nil) -> NetworkPacket {
        var body: [String: JSONValue] = [
            "filename": .string(name),
            "numberOfFiles": .int(1),
            "totalPayloadSize": .int(size),
        ]
        if let lastModifiedMillis { body["lastModified"] = .int(lastModifiedMillis) }

        return NetworkPacket(type: PacketType.shareRequest, body: body)
    }

    public static func linkPacket(_ url: String) -> NetworkPacket {
        NetworkPacket(type: PacketType.shareRequest, body: ["url": .string(url)])
    }

    public static func textPacket(_ text: String) -> NetworkPacket {
        NetworkPacket(type: PacketType.shareRequest, body: ["text": .string(text)])
    }

    public init?(packet: NetworkPacket) {
        guard packet.type == PacketType.shareRequest else { return nil }

        if let name = packet.string("filename") {
            guard let size = packet.payloadSize else { return nil }
            self = .file(name: name, size: size)
        } else if let url = packet.string("url") {
            self = .link(url)
        } else if let text = packet.string("text") {
            self = .text(text)
        } else {
            return nil
        }
    }

    /// A file name without any folders, so a peer can't write outside the download folder.
    public static func safeName(_ name: String) -> String {
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let trimmed = String(last.drop(while: { $0 == "." }))

        return trimmed.isEmpty ? "file" : trimmed
    }
}
