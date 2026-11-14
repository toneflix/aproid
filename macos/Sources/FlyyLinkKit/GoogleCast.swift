import Foundation

/// Where a Google Cast TV listens.
public struct CastEndpoint: Equatable, Hashable, Sendable {
    public var host: String
    public var port: UInt16

    public init(host: String, port: UInt16 = GoogleCast.port) {
        self.host = host
        self.port = port
    }
}

/// A Cast message's JSON payload.
public typealias CastJson = [String: Any]

/// Google Cast: the messages that tell a Cast TV's built-in media player what to play. Mirrors GoogleCast.kt.
public enum GoogleCast {
    public static let port: UInt16 = 8009
    public static let service = "_googlecast._tcp.local"

    /// Google's Default Media Receiver, the player every Cast TV has.
    public static let mediaReceiver = "CC1AD845"

    public static let sender = "sender-0"
    public static let receiver = "receiver-0"

    public static let connection = "urn:x-cast:com.google.cast.tp.connection"
    public static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    public static let receiverNamespace = "urn:x-cast:com.google.cast.receiver"
    public static let media = "urn:x-cast:com.google.cast.media"

    /// Replies that mean a request failed.
    public static let failures: Set<String> = ["LAUNCH_ERROR", "LOAD_FAILED", "LOAD_CANCELLED", "INVALID_REQUEST", "INVALID_PLAYER_STATE"]

    public static func connect() -> CastJson { ["type": "CONNECT"] }

    public static func ping() -> CastJson { ["type": "PING"] }

    public static func pong() -> CastJson { ["type": "PONG"] }

    public static func launch(_ requestId: Int) -> CastJson {
        ["type": "LAUNCH", "requestId": requestId, "appId": mediaReceiver]
    }

    public static func receiverStatus(_ requestId: Int) -> CastJson { ["type": "GET_STATUS", "requestId": requestId] }

    public static func stopApp(_ requestId: Int, sessionId: String) -> CastJson {
        ["type": "STOP", "requestId": requestId, "sessionId": sessionId]
    }

    public static func setVolume(_ requestId: Int, volume: Int) -> CastJson {
        ["type": "SET_VOLUME", "requestId": requestId, "volume": ["level": Double(min(max(volume, 0), 100)) / 100]]
    }

    public static func load(_ requestId: Int, url: String, title: String, mime: String) -> CastJson {
        [
            "type": "LOAD",
            "requestId": requestId,
            "autoplay": true,
            "media": [
                "contentId": url,
                "contentType": mime,
                "streamType": "BUFFERED",
                "metadata": ["metadataType": metadataType(mime), "title": title] as CastJson,
            ] as CastJson,
        ]
    }

    public static func mediaStatus(_ requestId: Int, mediaSessionId: Int64? = nil) -> CastJson {
        mediaCall("GET_STATUS", requestId, mediaSessionId)
    }

    public static func play(_ requestId: Int, mediaSessionId: Int64) -> CastJson { mediaCall("PLAY", requestId, mediaSessionId) }

    public static func pause(_ requestId: Int, mediaSessionId: Int64) -> CastJson { mediaCall("PAUSE", requestId, mediaSessionId) }

    public static func stop(_ requestId: Int, mediaSessionId: Int64) -> CastJson { mediaCall("STOP", requestId, mediaSessionId) }

    public static func seek(_ requestId: Int, mediaSessionId: Int64, positionMs: Int64) -> CastJson {
        ["type": "SEEK", "requestId": requestId, "mediaSessionId": mediaSessionId, "currentTime": Double(max(positionMs, 0)) / 1000]
    }

    /// The JSON text of a payload.
    public static func encode(_ payload: CastJson) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "{}" }

        return String(decoding: data, as: UTF8.self)
    }

    /// The JSON of a message, or nil when it isn't a JSON object.
    public static func parse(_ payload: String) -> CastJson? {
        (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? CastJson
    }

    public static func type(_ message: CastJson) -> String? { message["type"] as? String }

    public static func requestId(_ message: CastJson) -> Int? { (message["requestId"] as? NSNumber)?.intValue }

    /// The running Default Media Receiver in a RECEIVER_STATUS, or nil while it isn't running.
    public static func mediaApp(_ message: CastJson) -> CastApp? {
        guard type(message) == "RECEIVER_STATUS",
              let apps = (message["status"] as? CastJson)?["applications"] as? [CastJson],
              let app = apps.first(where: { $0["appId"] as? String == mediaReceiver }),
              let session = app["sessionId"] as? String,
              let transport = app["transportId"] as? String
        else { return nil }

        return CastApp(sessionId: session, transportId: transport)
    }

    /// The TV's volume from 0 to 100 in a RECEIVER_STATUS.
    public static func volume(_ message: CastJson) -> Int? {
        guard type(message) == "RECEIVER_STATUS",
              let level = (((message["status"] as? CastJson)?["volume"] as? CastJson)?["level"] as? NSNumber)?.doubleValue
        else { return nil }

        return Int((level * 100).rounded())
    }

    /// What the player is doing in a MEDIA_STATUS. Nil unless `message` is one.
    public static func media(_ message: CastJson) -> CastMedia? {
        guard type(message) == "MEDIA_STATUS" else { return nil }
        guard let status = (message["status"] as? [CastJson])?.first else { return CastMedia(mediaSessionId: nil, state: .stopped, position: nil) }

        let milliseconds = { (value: Any?) -> Int64? in (value as? NSNumber).map { Int64(($0.doubleValue * 1000).rounded(.towardZero)) } }
        let duration = milliseconds((status["media"] as? CastJson)?["duration"])

        return CastMedia(
            mediaSessionId: (status["mediaSessionId"] as? NSNumber)?.int64Value,
            state: state(status["playerState"] as? String),
            position: milliseconds(status["currentTime"]).map { CastPosition(position: $0, duration: max(duration ?? 0, 0)) }
        )
    }

    public static func state(_ playerState: String?) -> CastState? {
        switch playerState {
        case "PLAYING": return .playing
        case "PAUSED": return .paused
        case "BUFFERING": return .loading
        case "IDLE": return .stopped
        default: return nil
        }
    }

    /// 4 for photos, 3 for music and 1 for video: the Cast metadata types.
    private static func metadataType(_ mime: String) -> Int {
        switch CastKind.of(mime) {
        case .photo: return 4
        case .music: return 3
        default: return 1
        }
    }

    private static func mediaCall(_ type: String, _ requestId: Int, _ mediaSessionId: Int64?) -> CastJson {
        var call: CastJson = ["type": type, "requestId": requestId]
        if let mediaSessionId { call["mediaSessionId"] = mediaSessionId }
        return call
    }
}

/// The Default Media Receiver running on a TV: `transportId` is where media messages go.
public struct CastApp: Equatable, Sendable {
    public var sessionId: String
    public var transportId: String
}

/// What a Cast TV's player reports. A nil `state` means it reported nothing we know.
public struct CastMedia: Equatable, Sendable {
    public var mediaSessionId: Int64?
    public var state: CastState?
    public var position: CastPosition?
}

/// One Cast message, as sent over the TLS connection in a 4-byte length frame. Only text payloads are used.
public struct CastMessage: Equatable, Sendable {
    public var source: String
    public var destination: String
    public var namespace: String
    public var payload: String

    public init(source: String, destination: String, namespace: String, payload: String) {
        self.source = source
        self.destination = destination
        self.namespace = namespace
        self.payload = payload
    }

    /// The protobuf encoding of the message.
    public func encode() -> [UInt8] {
        var out: [UInt8] = [0x08, 0x00]

        Self.writeString(&out, field: 2, source)
        Self.writeString(&out, field: 3, destination)
        Self.writeString(&out, field: 4, namespace)
        out += [0x28, 0x00]
        Self.writeString(&out, field: 6, payload)

        return out
    }

    /// Reads a message, skipping fields it doesn't use. Nil if `bytes` isn't a whole message.
    public static func decode(_ bytes: [UInt8]) -> CastMessage? {
        var fields: [Int: String] = [:]
        var at = 0

        func varint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while at < bytes.count, shift < 64 {
                let b = bytes[at]
                at += 1
                value |= UInt64(b & 0x7f) << shift
                if b & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }

        while at < bytes.count {
            guard let tag = varint() else { return nil }
            let field = Int(tag >> 3)

            switch tag & 7 {
            case 0:
                guard varint() != nil else { return nil }
            case 1:
                at += 8
            case 2:
                guard let length = varint(), length <= UInt64(bytes.count - at) else { return nil }
                fields[field] = String(decoding: bytes[at..<at + Int(length)], as: UTF8.self)
                at += Int(length)
            case 5:
                at += 4
            default:
                return nil
            }
        }

        guard at <= bytes.count, let namespace = fields[4] else { return nil }

        return CastMessage(source: fields[2] ?? "", destination: fields[3] ?? "", namespace: namespace, payload: fields[6] ?? "")
    }

    private static func writeString(_ out: inout [UInt8], field: Int, _ text: String) {
        let bytes = Array(text.utf8)

        out.append(UInt8(field << 3 | 2))
        var length = bytes.count
        while length >= 0x80 {
            out.append(UInt8(length & 0x7f | 0x80))
            length >>= 7
        }
        out.append(UInt8(length))
        out += bytes
    }
}

/// One record from an mDNS answer. `data` is the target name (PTR), "port target" (SRV), the IPv4 address (A) or key=value lines (TXT).
public struct DnsRecord: Equatable, Sendable {
    public var name: String
    public var type: Int
    public var data: [String]
}

/// Multicast DNS, which Cast TVs answer to say where they are. Mirrors Mdns in GoogleCast.kt.
public enum Mdns {
    public static let address = "224.0.0.251"
    public static let port: UInt16 = 5353

    public static let a = 1
    public static let ptr = 12
    public static let txt = 16
    public static let srv = 33

    /// A question for `service`, asking for answers sent straight back to us.
    public static func query(_ service: String = GoogleCast.service) -> [UInt8] {
        var out: [UInt8] = [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]

        for label in service.split(separator: ".") {
            let bytes = Array(label.utf8)
            out.append(UInt8(bytes.count))
            out += bytes
        }
        out += [0, 0, UInt8(ptr), 0x80, 0x01]

        return out
    }

    /// The answer, authority and additional records in `packet`. Empty if it's malformed or a question.
    public static func parse(_ packet: [UInt8]) -> [DnsRecord] {
        var reader = DnsReader(bytes: packet)

        guard let flags = reader.u16(2), flags & 0x8000 != 0,
              let questions = reader.u16(4), let answers = reader.u16(6), let authority = reader.u16(8), let additional = reader.u16(10)
        else { return [] }

        reader.at = 12
        for _ in 0..<questions {
            guard reader.name() != nil else { return [] }
            reader.at += 4
        }

        var records: [DnsRecord] = []
        for _ in 0..<(answers + authority + additional) {
            guard let record = reader.record() else { return [] }
            if let record = record { records.append(record) }
        }

        return records
    }

    /// The Cast TVs in a set of records. `sender` is used when there is no address record.
    public static func castTvs(_ records: [DnsRecord], sender: String) -> [TvRenderer] {
        let service = GoogleCast.service.lowercased()

        return records.filter { $0.type == Mdns.ptr && $0.name.lowercased() == service }.compactMap { pointer -> TvRenderer? in
            guard let instance = pointer.data.first else { return nil }

            let location = records.first { $0.type == Mdns.srv && $0.name.caseInsensitiveCompare(instance) == .orderedSame }?.data.first?
                .split(separator: " ", maxSplits: 1).map(String.init)
            var fields: [String: String] = [:]
            for line in records.first(where: { $0.type == Mdns.txt && $0.name.caseInsensitiveCompare(instance) == .orderedSame })?.data ?? [] {
                guard let equals = line.firstIndex(of: "="), equals != line.startIndex else { continue }
                fields[line[..<equals].lowercased()] = String(line[line.index(after: equals)...])
            }

            let port = location?.first.flatMap { UInt16($0) } ?? GoogleCast.port
            let target = location.flatMap { $0.count > 1 ? $0[1] : nil }
            let host = target.flatMap { target in
                records.first { $0.type == Mdns.a && $0.name.caseInsensitiveCompare(target) == .orderedSame }?.data.first
            } ?? sender
            let name = fields["fn"].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                ?? String(instance.split(separator: ".").first ?? Substring(instance))

            return TvRenderer(id: "cast:" + (fields["id"] ?? instance), name: name, cast: CastEndpoint(host: host, port: port))
        }
    }
}

private struct DnsReader {
    let bytes: [UInt8]
    var at = 0

    func u8(_ offset: Int) -> Int? { offset >= 0 && offset < bytes.count ? Int(bytes[offset]) : nil }

    func u16(_ offset: Int) -> Int? {
        guard let high = u8(offset), let low = u8(offset + 1) else { return nil }
        return high << 8 | low
    }

    /// Nil when the record is malformed, and a nil record for types that aren't used.
    mutating func record() -> DnsRecord?? {
        guard let name = self.name(), let type = u16(at), let length = u16(at + 8) else { return nil }

        let start = at + 10
        let end = start + length
        guard end <= bytes.count else { return nil }

        at = start
        var data: [String]?
        switch type {
        case Mdns.ptr:
            guard let target = self.name() else { return nil }
            data = [target]
        case Mdns.srv:
            guard let port = u16(start + 4) else { return nil }
            at = start + 6
            guard let target = self.name() else { return nil }
            data = ["\(port) \(target)"]
        case Mdns.a:
            data = length == 4 ? [bytes[start..<end].map { String($0) }.joined(separator: ".")] : nil
        case Mdns.txt:
            var lines: [String] = []
            var i = start
            while i < end {
                let size = Int(bytes[i])
                if i + 1 + size > end { break }
                lines.append(String(decoding: bytes[(i + 1)..<(i + 1 + size)], as: UTF8.self))
                i += 1 + size
            }
            data = lines
        default:
            data = nil
        }
        at = end

        return .some(data.map { DnsRecord(name: name, type: type, data: $0) })
    }

    /// Reads a name at `at`, following compression pointers.
    mutating func name() -> String? {
        var labels: [String] = []
        var offset = at
        var jumped = false
        var jumps = 0

        while true {
            guard let size = u8(offset) else { return nil }

            if size == 0 {
                if !jumped { at = offset + 1 }
                return labels.joined(separator: ".")
            } else if size & 0xc0 == 0xc0 {
                jumps += 1
                guard jumps <= 16, let low = u8(offset + 1) else { return nil }
                if !jumped { at = offset + 2 }
                offset = (size & 0x3f) << 8 | low
                jumped = true
            } else {
                guard offset + 1 + size <= bytes.count else { return nil }
                labels.append(String(decoding: bytes[(offset + 1)..<(offset + 1 + size)], as: UTF8.self))
                offset += 1 + size
            }
        }
    }
}
