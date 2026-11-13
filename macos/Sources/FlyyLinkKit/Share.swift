import Foundation

/// What a "kdeconnect.share.request" carries: a file, a link or some text. Mirrors Share.kt.
public enum Share: Equatable, Sendable {
    /// `transferId` lets an interrupted file be resumed; `offset` is where this payload starts in the file,
    /// so `size` is only what is left. Both are our own fields, which KDE Connect ignores.
    case file(name: String, size: Int64, transferId: String? = nil, offset: Int64 = 0)
    case link(String)
    case text(String)

    /// The packet announcing a file. Send it with `Device.sendWithPayload`, which adds the payload.
    public static func filePacket(
        name: String,
        size: Int64,
        lastModifiedMillis: Int64? = nil,
        transferId: String? = nil,
        offset: Int64 = 0
    ) -> NetworkPacket {
        var body: [String: JSONValue] = [
            "filename": .string(name),
            "numberOfFiles": .int(1),
            "totalPayloadSize": .int(size),
        ]
        if let lastModifiedMillis { body["lastModified"] = .int(lastModifiedMillis) }
        if let transferId { body["flyylink.transferId"] = .string(transferId) }
        if offset > 0 { body["flyylink.offset"] = .int(offset) }

        return NetworkPacket(type: PacketType.shareRequest, body: body)
    }

    /// Asks the sender for the rest of `transferId`, from byte `offset`.
    public static func resumePacket(transferId: String, offset: Int64) -> NetworkPacket {
        NetworkPacket(type: PacketType.shareResume, body: ["transferId": .string(transferId), "offset": .int(offset)])
    }

    /// The transfer and offset a resume packet asks for.
    public static func resumeRequest(_ packet: NetworkPacket) -> (transferId: String, offset: Int64)? {
        guard packet.type == PacketType.shareResume,
              let id = packet.string("transferId"),
              let offset = packet.int("offset"), offset >= 0
        else { return nil }

        return (id, offset)
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
            let offset = max(packet.int("flyylink.offset") ?? 0, 0)
            self = .file(name: name, size: size, transferId: packet.string("flyylink.transferId"), offset: offset)
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
