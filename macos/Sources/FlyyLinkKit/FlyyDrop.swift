import Foundation

/// Lets some packets pass to and from a device that is not paired. `Device` asks before delivering or sending one.
public protocol GuestAccess: AnyObject {
    /// True when `packet` from the unpaired `deviceId` may reach the plugins.
    func admitsIncoming(from deviceId: String, _ packet: NetworkPacket) -> Bool

    /// True when `packet` may go to the unpaired `deviceId`.
    func admitsOutgoing(to deviceId: String, _ packet: NetworkPacket) -> Bool
}

/// FlyyDrop: AirDrop-style sharing with any nearby FlyyLink device, paired or not.
///
/// The sender asks first with "flyylink.flyydrop.request", listing the files or the link or text. The receiver's user
/// accepts or declines ("flyylink.flyydrop.response"), and only then do the items arrive as ordinary
/// "kdeconnect.share.request" packets tagged with the request's id. An unpaired device gets nothing more: as its
/// `GuestAccess`, this class lets in exactly the accepted items, once each. Mirrors FlyyDrop.kt and FlyyDrop.cs.
public final class FlyyDrop: GuestAccess {
    /// Who may send this device a request without being paired.
    public enum Receiving: String, CaseIterable, Sendable {
        case off, everyoneFor10Minutes, everyone
    }

    /// Why a request was turned down.
    public enum Reason: String, Sendable {
        case declined, unavailable, busy

        public init(wire: String?) {
            self = wire.flatMap(Reason.init(rawValue:)) ?? .declined
        }
    }

    public struct Item: Equatable, Hashable, Sendable {
        public var name: String
        public var size: Int64

        public init(name: String, size: Int64) {
            self.name = name
            self.size = size
        }

        public var safeName: String { Share.safeName(name) }
    }

    /// One request: files, or a link or some text, between this device and `deviceId`.
    public struct Offer: Equatable, Sendable {
        public var id: String
        public var deviceId: String
        public var items: [Item]
        public var text: String?

        public init(id: String, deviceId: String, items: [Item], text: String? = nil) {
            self.id = id
            self.deviceId = deviceId
            self.items = items
            self.text = text
        }

        public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    }

    /// What to do with a request that arrived: ask the user, or send `packet` straight back.
    public enum Incoming: Equatable, Sendable {
        case ask(Offer)
        case reply(NetworkPacket)
    }

    /// The receiver's answer to one of our requests.
    public struct Answer: Equatable, Sendable {
        public var offer: Offer
        public var accepted: Bool
        public var reason: Reason?
    }

    /// How long a request waits for the user to answer, in milliseconds.
    public static let askMs: Int64 = 60_000

    /// How long an accepted request waits for its next item.
    public static let acceptedMs: Int64 = 60 * 60_000

    /// How long "Everyone for 10 minutes" lasts.
    public static let everyoneMs: Int64 = 10 * 60_000

    /// Requests waiting for an answer at once, from all devices.
    public static let maxAsking = 3

    public static let maxItems = 1000
    public static let maxText = 64 * 1024

    /// The share packet field that says which request an item belongs to.
    public static let tag = "flyylink.flyydrop"

    /// The sender waits a little longer than the receiver, so the receiver's answer always wins.
    private static let graceMs: Int64 = 5_000

    private enum Stage { case asking, accepted }

    private final class Transfer {
        let offer: Offer
        var stage: Stage
        var expires: Int64
        var waiting: [Item]
        var textWaiting: Bool

        init(_ offer: Offer, stage: Stage, expires: Int64) {
            self.offer = offer
            self.stage = stage
            self.expires = expires
            waiting = offer.items
            textWaiting = offer.text != nil
        }

        var isDone: Bool { waiting.isEmpty && !textWaiting }

        func matches(_ deviceId: String, _ stage: Stage) -> Bool { offer.deviceId == deviceId && self.stage == stage }
    }

    private let clock: () -> Int64
    private let lock = NSLock()
    private var incoming: [String: Transfer] = [:]
    private var outgoing: [String: Transfer] = [:]
    private var mode = Receiving.off
    private var everyoneUntil: Int64 = 0

    public init(clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.clock = clock
    }

    /// Who may send a request now. "Everyone for 10 minutes" reads as off once the time is up.
    public var receiving: Receiving {
        get { lock.withLock { currentReceiving } }
        set {
            lock.withLock {
                mode = newValue
                everyoneUntil = clock() + Self.everyoneMs
            }
        }
    }

    /// When "Everyone for 10 minutes" ends, in milliseconds, or nil for the other settings.
    public var receivingUntil: Int64? {
        lock.withLock { currentReceiving == .everyoneFor10Minutes ? everyoneUntil : nil }
    }

    /// Puts back a setting saved earlier, keeping its original end time.
    public func restore(_ mode: Receiving, until: Int64?) {
        lock.withLock {
            self.mode = mode
            everyoneUntil = until ?? 0
        }
    }

    private var currentReceiving: Receiving {
        mode == .everyoneFor10Minutes && clock() >= everyoneUntil ? .off : mode
    }

    // MARK: Sending

    /// Starts a request to `deviceId`. Send the returned packet, then wait for `onResponse`.
    public func request(to deviceId: String, items: [Item], text: String? = nil) -> NetworkPacket {
        let text = text.flatMap { $0.isEmpty ? nil : $0 }
        precondition(!items.isEmpty || text != nil, "nothing to send")

        let offer = Offer(id: UUID().uuidString, deviceId: deviceId, items: items, text: text)
        lock.withLock { outgoing[offer.id] = Transfer(offer, stage: .asking, expires: clock() + Self.askMs + Self.graceMs) }

        return Self.requestPacket(offer)
    }

    /// Reads the receiver's answer to one of our requests.
    public func onResponse(from deviceId: String, _ packet: NetworkPacket) -> Answer? {
        guard packet.type == PacketType.flyyDropResponse, let id = packet.string("id") else { return nil }

        return lock.withLock {
            guard let transfer = outgoing[id], transfer.matches(deviceId, .asking) else { return nil }

            let accepted = packet.bool("accept") == true
            if accepted {
                transfer.stage = .accepted
                transfer.expires = clock() + Self.acceptedMs
            } else {
                outgoing[id] = nil
            }

            return Answer(offer: transfer.offer, accepted: accepted, reason: accepted ? nil : Reason(wire: packet.string("reason")))
        }
    }

    // MARK: Receiving

    /// Decides what to do with a request from `deviceId`. Returns nil for a malformed or repeated one.
    public func onRequest(from deviceId: String, _ packet: NetworkPacket, isPaired: Bool) -> Incoming? {
        guard let offer = Self.offer(from: deviceId, packet) else { return nil }

        return lock.withLock {
            guard incoming[offer.id] == nil else { return nil }

            if !isPaired && currentReceiving == .off { return .reply(Self.response(offer.id, .unavailable)) }

            let asking = incoming.values.filter { $0.stage == .asking }
            if asking.count >= Self.maxAsking || asking.contains(where: { $0.offer.deviceId == deviceId }) {
                return .reply(Self.response(offer.id, .busy))
            }

            incoming[offer.id] = Transfer(offer, stage: .asking, expires: clock() + Self.askMs)

            return .ask(offer)
        }
    }

    /// The user accepted. Send the returned packet; the items may then come in.
    public func accept(_ id: String) -> NetworkPacket? {
        lock.withLock {
            guard let transfer = incoming[id], transfer.stage == .asking else { return nil }

            transfer.stage = .accepted
            transfer.expires = clock() + Self.acceptedMs

            return NetworkPacket(type: PacketType.flyyDropResponse, body: ["id": .string(id), "accept": true])
        }
    }

    /// The user declined. Send the returned packet.
    public func decline(_ id: String) -> NetworkPacket? {
        lock.withLock {
            guard incoming.removeValue(forKey: id) != nil else { return nil }

            return Self.response(id, .declined)
        }
    }

    // MARK: Either side

    /// Stops a request in either direction. Send the returned packet to tell the other device.
    public func cancel(_ id: String) -> NetworkPacket? {
        lock.withLock {
            guard incoming.removeValue(forKey: id) != nil || outgoing.removeValue(forKey: id) != nil else { return nil }

            return NetworkPacket(type: PacketType.flyyDropCancel, body: ["id": .string(id)])
        }
    }

    /// The other device stopped a request. Returns it, so its prompt or progress can go away.
    public func onCancel(from deviceId: String, _ packet: NetworkPacket) -> Offer? {
        guard packet.type == PacketType.flyyDropCancel, let id = packet.string("id") else { return nil }

        return lock.withLock {
            if incoming[id]?.offer.deviceId == deviceId { return incoming.removeValue(forKey: id)?.offer }
            if outgoing[id]?.offer.deviceId == deviceId { return outgoing.removeValue(forKey: id)?.offer }

            return nil
        }
    }

    /// Forgets requests nobody answered and accepted ones that went quiet, and returns them. Call every few seconds.
    public func expire() -> [Offer] {
        lock.withLock {
            let now = clock()
            let expired = (Array(incoming.values) + Array(outgoing.values)).filter { $0.expires <= now }.map(\.offer)

            incoming = incoming.filter { $0.value.expires > now }
            outgoing = outgoing.filter { $0.value.expires > now }

            return expired
        }
    }

    /// True while `id` is waiting for an answer or still has items to move.
    public func isActive(_ id: String) -> Bool {
        lock.withLock { incoming[id] != nil || outgoing[id] != nil }
    }

    // MARK: GuestAccess

    public func admitsIncoming(from deviceId: String, _ packet: NetworkPacket) -> Bool {
        lock.withLock {
            switch packet.type {
            case PacketType.flyyDropRequest, PacketType.flyyDropCancel:
                return true
            case PacketType.flyyDropResponse:
                return packet.string("id").flatMap { outgoing[$0] }?.matches(deviceId, .asking) == true
            case PacketType.shareRequest:
                return take(from: &incoming, deviceId, packet, size: packet.payloadSize)
            default:
                return false
            }
        }
    }

    public func admitsOutgoing(to deviceId: String, _ packet: NetworkPacket) -> Bool {
        lock.withLock {
            switch packet.type {
            case PacketType.flyyDropRequest:
                return packet.string("id").flatMap { outgoing[$0] }?.matches(deviceId, .asking) == true
            case PacketType.flyyDropCancel:
                return true
            case PacketType.flyyDropResponse:
                return packet.bool("accept") != true
                    || packet.string("id").flatMap { incoming[$0] }?.matches(deviceId, .accepted) == true
            case PacketType.shareRequest:
                return take(from: &outgoing, deviceId, packet, size: packet.int("totalPayloadSize"))
            default:
                return false
            }
        }
    }

    /// Lets one accepted item through, once, and forgets the request after its last item.
    private func take(from transfers: inout [String: Transfer], _ deviceId: String, _ packet: NetworkPacket, size: Int64?) -> Bool {
        guard let id = packet.string(Self.tag), let transfer = transfers[id], transfer.matches(deviceId, .accepted) else { return false }

        if let name = packet.string("filename") {
            guard (packet.int("flyylink.offset") ?? 0) == 0,
                  let index = transfer.waiting.firstIndex(of: Item(name: name, size: size ?? -1))
            else { return false }

            transfer.waiting.remove(at: index)
        } else if let text = packet.string("url") ?? packet.string("text"), transfer.textWaiting, text == transfer.offer.text {
            transfer.textWaiting = false
        } else {
            return false
        }

        if transfer.isDone {
            transfers[id] = nil
        } else {
            transfer.expires = clock() + Self.acceptedMs
        }

        return true
    }

    // MARK: Packets

    /// A file of an accepted request. Send it with `Device.sendWithPayload`.
    public static func file(_ id: String, _ item: Item) -> NetworkPacket {
        tagged(Share.filePacket(name: item.name, size: item.size), id)
    }

    /// The link or text of an accepted request.
    public static func text(_ id: String, _ text: String) -> NetworkPacket {
        let isLink = text.range(of: "^https?://\\S+$", options: [.regularExpression, .caseInsensitive]) != nil

        return tagged(isLink ? Share.linkPacket(text) : Share.textPacket(text), id)
    }

    /// The request an item belongs to, or nil for an ordinary share.
    public static func requestId(_ packet: NetworkPacket) -> String? { packet.string(tag) }

    public static func requestPacket(_ offer: Offer) -> NetworkPacket {
        var body: [String: JSONValue] = [
            "id": .string(offer.id),
            "files": .array(offer.items.map { .object(["name": .string($0.name), "size": .int($0.size)]) }),
        ]
        if let text = offer.text { body["text"] = .string(text) }

        return NetworkPacket(type: PacketType.flyyDropRequest, body: body)
    }

    /// Reads a request, or nil when it is malformed or too big.
    public static func offer(from deviceId: String, _ packet: NetworkPacket) -> Offer? {
        guard packet.type == PacketType.flyyDropRequest,
              let id = packet.string("id"), !id.isEmpty, id.utf16.count <= 64
        else { return nil }

        let files = packet.body["files"]?.arrayValue ?? []
        guard files.count <= maxItems else { return nil }

        var items: [Item] = []
        for file in files {
            guard let json = file.objectValue,
                  let name = json["name"]?.stringValue, !name.trimmingCharacters(in: .whitespaces).isEmpty,
                  let size = json["size"]?.intValue, size >= 0
            else { return nil }

            items.append(Item(name: name, size: size))
        }

        let text = packet.string("text").flatMap { $0.isEmpty ? nil : $0 }
        if let text, text.utf16.count > maxText { return nil }
        guard !items.isEmpty || text != nil else { return nil }

        return Offer(id: id, deviceId: deviceId, items: items, text: text)
    }

    private static func response(_ id: String, _ reason: Reason) -> NetworkPacket {
        NetworkPacket(type: PacketType.flyyDropResponse, body: ["id": .string(id), "accept": false, "reason": .string(reason.rawValue)])
    }

    private static func tagged(_ packet: NetworkPacket, _ id: String) -> NetworkPacket {
        var tagged = packet
        tagged.body[tag] = .string(id)

        return tagged
    }
}
