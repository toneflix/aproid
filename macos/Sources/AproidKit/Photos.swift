import Foundation

/// One photo or video in the phone's gallery. `date` is when it was taken, in milliseconds; `thumbnail` is base64 JPEG.
/// Mirrors PhonePhoto in Photos.kt.
public struct PhonePhoto: Equatable, Identifiable, Sendable {
    public var id: Int64
    public var name: String
    public var date: Int64
    public var mimeType: String
    public var width: Int64
    public var height: Int64
    public var size: Int64
    public var thumbnail: String?

    public init(
        id: Int64,
        name: String,
        date: Int64,
        mimeType: String,
        width: Int64 = 0,
        height: Int64 = 0,
        size: Int64 = 0,
        thumbnail: String? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.size = size
        self.thumbnail = thumbnail
    }

    public var isVideo: Bool { mimeType.hasPrefix("video/") }

    public init?(json: [String: JSONValue]) {
        guard let id = json["id"]?.intValue else { return nil }

        self.init(
            id: id,
            name: json["name"]?.stringValue ?? "",
            date: json["date"]?.intValue ?? 0,
            mimeType: json["mimeType"]?.stringValue ?? "image/jpeg",
            width: json["width"]?.intValue ?? 0,
            height: json["height"]?.intValue ?? 0,
            size: json["size"]?.intValue ?? 0,
            thumbnail: json["thumbnail"]?.stringValue
        )
    }

    public func toJSON() -> JSONValue {
        var json: [String: JSONValue] = [
            "id": .int(id),
            "name": .string(name),
            "date": .int(date),
            "mimeType": .string(mimeType),
            "width": .int(width),
            "height": .int(height),
            "size": .int(size),
        ]
        if let thumbnail { json["thumbnail"] = .string(thumbnail) }
        return .object(json)
    }
}

/// Browsing the phone's gallery from the Mac. Full photos come back as normal shared files. Mirrors Photos.kt.
public enum Photos {
    public static let page = 40

    public struct Request: Equatable, Sendable {
        public var before: Int64?
        public var count: Int64
    }

    public struct Page: Equatable, Sendable {
        public var photos: [PhonePhoto]
        public var more: Bool
    }

    public static func request(before: Int64? = nil, count: Int64 = Int64(page)) -> NetworkPacket {
        var body: [String: JSONValue] = ["count": .int(count)]
        if let before { body["before"] = .int(before) }
        return NetworkPacket(type: PacketType.photosRequest, body: body)
    }

    public static func request(_ packet: NetworkPacket) -> Request? {
        guard packet.type == PacketType.photosRequest else { return nil }

        let before = packet.int("before").flatMap { $0 > 0 ? $0 : nil }
        return Request(before: before, count: min(max(packet.int("count") ?? Int64(page), 1), 200))
    }

    public static func pagePacket(_ photos: [PhonePhoto], more: Bool) -> NetworkPacket {
        NetworkPacket(type: PacketType.photos, body: [
            "photos": .array(photos.map { $0.toJSON() }),
            "more": .bool(more),
        ])
    }

    public static func page(_ packet: NetworkPacket) -> Page? {
        guard packet.type == PacketType.photos else { return nil }

        let photos = (packet.body["photos"]?.arrayValue ?? []).compactMap { $0.objectValue.flatMap(PhonePhoto.init(json:)) }
        return Page(photos: photos, more: packet.bool("more") ?? false)
    }

    public static func download(id: Int64) -> NetworkPacket {
        NetworkPacket(type: PacketType.photosDownload, body: ["id": .int(id)])
    }

    public static func downloadId(_ packet: NetworkPacket) -> Int64? {
        packet.type == PacketType.photosDownload ? packet.int("id") : nil
    }
}
