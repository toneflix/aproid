import Foundation
import Network

/// Finds Google Cast TVs over mDNS. Mirrors GoogleCastNetwork.kt.
public enum CastFinder {
    /// Asks for `timeout` seconds and returns each TV once, sorted by name.
    public static func search(timeout: TimeInterval = 3) async -> [TvRenderer] {
        await Task.detached { collect(timeout: timeout) }.value
    }

    /// Sends the question and gathers every Cast TV that answers. Blocks.
    private static func collect(timeout: TimeInterval) -> [TvRenderer] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var group = sockaddr_in()
        group.sin_family = sa_family_t(AF_INET)
        group.sin_port = Mdns.port.bigEndian
        inet_pton(AF_INET, Mdns.address, &group.sin_addr)

        // Sent twice, since multicast over Wi-Fi drops packets.
        let query = Mdns.query()
        for _ in 0..<2 {
            _ = withUnsafePointer(to: &group) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, query, query.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var found: [String: TvRenderer] = [:]
        var buffer = [UInt8](repeating: 0, count: 9000)
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            let left = deadline.timeIntervalSinceNow
            if left <= 0 { break }

            var wait = timeval(tv_sec: Int(left), tv_usec: Int32((left - floor(left)) * 1_000_000))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            if count <= 0 { break }

            var address = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &address, socklen_t(INET_ADDRSTRLEN))

            for tv in Mdns.castTvs(Mdns.parse(Array(buffer[0..<count])), sender: String(cString: address)) {
                found[tv.id] = tv
            }
        }

        return found.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

/// A TLS connection to a Cast TV that answers its heartbeats and matches replies to requests.
public final class CastChannel: @unchecked Sendable {
    private struct Waiter {
        let match: (CastJson) -> Bool
        let continuation: CheckedContinuation<CastJson, Error>
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "cast-channel")
    private let lock = NSLock()
    private var waiters: [UUID: Waiter] = [:]
    private var nextId = 1
    private var open = true
    private var pinger: DispatchSourceTimer?

    public var isOpen: Bool { lock.withLock { open } }

    private init(_ connection: NWConnection) {
        self.connection = connection
    }

    /// Connects and starts answering heartbeats.
    public static func connect(_ endpoint: CastEndpoint) async throws -> CastChannel {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else { throw ProtocolError("bad Cast port") }

        let tls = NWProtocolTLS.Options()
        // Cast TVs use self-signed certificates.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, DispatchQueue.global())

        let channel = CastChannel(NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: NWParameters(tls: tls)))
        try await channel.start()

        return channel
    }

    public func newRequestId() -> Int {
        lock.withLock {
            defer { nextId += 1 }
            return nextId
        }
    }

    public func send(_ namespace: String, _ destination: String, _ payload: CastJson) {
        let bytes = CastMessage(source: GoogleCast.sender, destination: destination, namespace: namespace, payload: GoogleCast.encode(payload)).encode()
        let length = UInt32(bytes.count).bigEndian
        let frame = withUnsafeBytes(of: length) { Data($0) } + Data(bytes)

        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    /// Sends `payload` and waits for the first message that `match`es.
    public func request(
        _ namespace: String,
        _ destination: String,
        _ payload: CastJson,
        timeout: TimeInterval = 5,
        match: @escaping (CastJson) -> Bool
    ) async throws -> CastJson {
        let key = UUID()
        let type = GoogleCast.type(payload) ?? "a request"

        return try await withCheckedThrowingContinuation { continuation in
            let added = lock.withLock { () -> Bool in
                guard open else { return false }
                waiters[key] = Waiter(match: match, continuation: continuation)
                return true
            }
            guard added else {
                continuation.resume(throwing: ProtocolError("not connected to the TV"))
                return
            }

            send(namespace, destination, payload)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(key, .failure(ProtocolError("the TV didn't answer \(type)")))
            }
        }
    }

    public func close() {
        let pending = lock.withLock { () -> [Waiter] in
            open = false
            defer { waiters.removeAll() }
            return Array(waiters.values)
        }

        pinger?.cancel()
        connection.cancel()
        pending.forEach { $0.continuation.resume(throwing: ProtocolError("the TV closed the connection")) }
    }

    private func start() async throws {
        let once = Once()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume() }
                case .failed(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                    self?.close()
                case .cancelled:
                    if once.claim() { continuation.resume(throwing: ProtocolError("the connection to the TV closed")) }
                default:
                    break
                }
            }
            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard once.claim() else { return }
                continuation.resume(throwing: ProtocolError("the TV didn't answer"))
                self?.connection.cancel()
            }
        }

        receiveFrame()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.send(GoogleCast.heartbeat, GoogleCast.receiver, GoogleCast.ping()) }
        timer.resume()
        pinger = timer
    }

    private func receiveFrame() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] head, _, _, error in
            guard let self else { return }
            guard error == nil, let head, head.count == 4 else { return self.close() }

            let length = Int(head.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            guard length <= 1 << 20 else { return self.close() }

            self.connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, error in
                guard let self else { return }
                guard error == nil, let body, body.count == length else { return self.close() }

                if self.handle(CastMessage.decode(Array(body))) { self.receiveFrame() }
            }
        }
    }

    /// False once the TV closed the session.
    private func handle(_ message: CastMessage?) -> Bool {
        guard let message, let json = GoogleCast.parse(message.payload) else { return true }

        let type = GoogleCast.type(json)
        if message.namespace == GoogleCast.heartbeat, type == "PING" {
            send(GoogleCast.heartbeat, message.source, GoogleCast.pong())
        } else if message.namespace == GoogleCast.connection, type == "CLOSE" {
            close()
            return false
        } else if let key = lock.withLock({ waiters.first { $0.value.match(json) }?.key }) {
            finish(key, .success(json))
        }

        return true
    }

    private func finish(_ key: UUID, _ result: Result<CastJson, Error>) {
        guard let waiter = lock.withLock({ waiters.removeValue(forKey: key) }) else { return }

        waiter.continuation.resume(with: result)
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.withLock {
                defer { claimed = true }
                return !claimed
            }
        }
    }
}

/// Plays on a Cast TV through its Default Media Receiver.
actor CastControl: TvControl {
    private let endpoint: CastEndpoint
    private var channel: CastChannel?
    private var app: CastApp?
    private var mediaSessionId: Int64?
    private var duration: Int64 = 0

    init(endpoint: CastEndpoint) {
        self.endpoint = endpoint
    }

    func play(url: String, title: String, mime: String, size: Int64?) async throws {
        channel?.close()

        let opened = try await CastChannel.connect(endpoint)
        channel = opened
        opened.send(GoogleCast.connection, GoogleCast.receiver, GoogleCast.connect())

        let id = opened.newRequestId()
        let reply = try await opened.request(GoogleCast.receiverNamespace, GoogleCast.receiver, GoogleCast.launch(id), timeout: 15) {
            GoogleCast.mediaApp($0) != nil || (GoogleCast.requestId($0) == id && GoogleCast.failures.contains(GoogleCast.type($0) ?? ""))
        }
        guard let launched = GoogleCast.mediaApp(reply) else { throw ProtocolError("the TV couldn't open its media player") }

        app = launched
        duration = 0
        opened.send(GoogleCast.connection, launched.transportId, GoogleCast.connect())

        mediaSessionId = GoogleCast.media(try await media(timeout: 15) { GoogleCast.load($0, url: url, title: title, mime: mime) })?.mediaSessionId
    }

    func resume() async throws {
        let session = try session()
        _ = try await media { GoogleCast.play($0, mediaSessionId: session) }
    }

    func pause() async throws {
        let session = try session()
        _ = try await media { GoogleCast.pause($0, mediaSessionId: session) }
    }

    func stop() async throws {
        guard let opened = channel else { return }

        if let session = mediaSessionId {
            _ = try? await media { GoogleCast.stop($0, mediaSessionId: session) }
        }
        if let running = app {
            _ = try? await receiver { GoogleCast.stopApp($0, sessionId: running.sessionId) }
        }
        opened.close()
        channel = nil
        app = nil
    }

    func seek(_ positionMs: Int64) async throws {
        let session = try session()
        _ = try await media { GoogleCast.seek($0, mediaSessionId: session, positionMs: positionMs) }
    }

    func position() async throws -> CastPosition? {
        guard let position = try await status()?.position else { return nil }

        if position.duration > 0 { duration = position.duration }
        return CastPosition(position: position.position, duration: duration)
    }

    func state() async throws -> CastState? {
        guard channel?.isOpen == true else { return .stopped }

        return try await status()?.state
    }

    func volume() async throws -> Int? {
        GoogleCast.volume(try await receiver { GoogleCast.receiverStatus($0) })
    }

    func setVolume(_ volume: Int) async throws {
        _ = try await receiver { GoogleCast.setVolume($0, volume: volume) }
    }

    private func status() async throws -> CastMedia? {
        guard channel?.isOpen == true else { return nil }

        let status = GoogleCast.media(try await media { GoogleCast.mediaStatus($0) })
        if let id = status?.mediaSessionId { mediaSessionId = id }

        return status
    }

    private func session() throws -> Int64 {
        guard let mediaSessionId else { throw ProtocolError("nothing is playing on the TV") }
        return mediaSessionId
    }

    private func media(timeout: TimeInterval = 5, _ build: (Int) -> CastJson) async throws -> CastJson {
        guard let target = app else { throw ProtocolError("the TV's media player isn't open") }

        return try await call(GoogleCast.media, target.transportId, timeout, build)
    }

    private func receiver(_ build: (Int) -> CastJson) async throws -> CastJson {
        try await call(GoogleCast.receiverNamespace, GoogleCast.receiver, 5, build)
    }

    private func call(_ namespace: String, _ destination: String, _ timeout: TimeInterval, _ build: (Int) -> CastJson) async throws -> CastJson {
        guard let opened = channel, opened.isOpen else { throw ProtocolError("not connected to the TV") }

        let id = opened.newRequestId()
        let payload = build(id)

        let reply = try await opened.request(namespace, destination, payload, timeout: timeout) { GoogleCast.requestId($0) == id }
        if let type = GoogleCast.type(reply), GoogleCast.failures.contains(type) {
            throw ProtocolError("the TV refused \(GoogleCast.type(payload) ?? "a request")")
        }

        return reply
    }
}
