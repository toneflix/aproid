import Foundation
import Network

/// A peer we found on the network and exchanged identities with.
public struct DiscoveredPeer: Equatable, Sendable {
    public let identity: DeviceIdentity
    public let host: String
}

/// LAN discovery and the plain-text identity exchange from the KDE Connect protocol.
///
/// 1. We broadcast our identity over UDP to port 1716.
/// 2. A peer that hears it opens a TCP connection to our tcpPort and sends its identity.
/// 3. Both sides then upgrade the socket to TLS (not done here yet: see docs/ARCHITECTURE.md).
///
/// Mirrors android/protocol/.../LanLink.kt.
public final class LanLink {
    public typealias PeerHandler = (DiscoveredPeer, NWConnection) -> Void

    private let queue = DispatchQueue(label: "aproid.lanlink")
    private let identityProvider: () -> DeviceIdentity
    private let onPeer: PeerHandler
    private let udpPortNumber: UInt16
    private let tcpPorts: ClosedRange<UInt16>
    private var tcpListener: NWListener?
    private var udpListener: NWListener?

    /// Port the TCP listener is bound to, once it is ready.
    public private(set) var tcpPort: UInt16?

    public init(
        identityProvider: @escaping () -> DeviceIdentity,
        udpPort: UInt16 = AproidKit.udpPort,
        tcpPorts: ClosedRange<UInt16> = AproidKit.tcpPortRange,
        onPeer: @escaping PeerHandler
    ) {
        self.identityProvider = identityProvider
        self.onPeer = onPeer
        self.udpPortNumber = udpPort
        self.tcpPorts = tcpPorts
    }

    public func start() {
        queue.async {
            self.startTCP(port: self.tcpPorts.lowerBound)
            self.startUDP()
        }
    }

    public func stop() {
        queue.async {
            self.tcpListener?.cancel()
            self.udpListener?.cancel()
            self.tcpListener = nil
            self.udpListener = nil
            self.tcpPort = nil
        }
    }

    /// Send our identity to everyone on the local network.
    /// Network.framework cannot send broadcasts, so this uses a plain BSD socket.
    public func broadcastIdentity(to address: String = "255.255.255.255") {
        guard let data = try? currentIdentity().toPacket().serialize() else { return }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = udpPortNumber.bigEndian
        inet_pton(AF_INET, address, &addr.sin_addr)
        _ = data.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    /// Connect to a peer that announced itself, and send our identity.
    public func connect(to peer: DeviceIdentity, host: String) {
        guard let port = peer.tcpPort, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                guard let data = try? self.currentIdentity().toPacket().serialize() else { return }
                conn.send(content: data, completion: .contentProcessed { _ in })
                self.onPeer(DiscoveredPeer(identity: peer, host: host), conn)
            }
        }
        conn.start(queue: queue)
    }

    private func currentIdentity() -> DeviceIdentity {
        var id = identityProvider()
        id.tcpPort = tcpPort
        return id
    }

    // MARK: TCP

    private func startTCP(port: UInt16) {
        guard tcpPorts.contains(port), let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params, on: nwPort) else {
            startTCP(port: port + 1)
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.tcpPort = port
            case .failed:
                listener.cancel()
                // Port taken (for example by KDE Connect): try the next one.
                self.startTCP(port: port + 1)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.handleIncoming(conn) }
        tcpListener = listener
        listener.start(queue: queue)
    }

    private func handleIncoming(_ conn: NWConnection) {
        conn.start(queue: queue)
        Self.readLine(conn) { [weak self] line in
            guard let self, let line,
                  let packet = try? NetworkPacket.parse(line),
                  let identity = try? DeviceIdentity(packet: packet),
                  identity.deviceId != self.identityProvider().deviceId
            else {
                conn.cancel()
                return
            }
            let host: String
            if case .hostPort(let h, _) = conn.endpoint { host = "\(h)" } else { host = "" }
            self.onPeer(DiscoveredPeer(identity: identity, host: host), conn)
        }
    }

    /// Reads up to the first newline. Peers send nothing after their identity until TLS starts.
    static func readLine(_ conn: NWConnection, buffer: Data = Data(), completion: @escaping (String?) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            var buf = buffer
            if let data { buf.append(data) }
            if let idx = buf.firstIndex(of: 0x0A) {
                completion(String(decoding: buf[buf.startIndex..<idx], as: UTF8.self))
            } else if isComplete || error != nil || buf.count > 1_000_000 {
                completion(nil)
            } else {
                readLine(conn, buffer: buf, completion: completion)
            }
        }
    }

    // MARK: UDP

    private func startUDP() {
        guard let nwPort = NWEndpoint.Port(rawValue: udpPortNumber) else { return }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        // If the port is taken (for example by KDE Connect) we can still be found over TCP.
        guard let listener = try? NWListener(using: params, on: nwPort) else { return }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: self.queue)
            conn.receiveMessage { [weak self] data, _, _, _ in
                defer { conn.cancel() }
                guard let self, let data,
                      let packet = try? NetworkPacket.parse(data),
                      let identity = try? DeviceIdentity(packet: packet),
                      identity.deviceId != self.identityProvider().deviceId,
                      case .hostPort(let host, _) = conn.endpoint
                else { return }
                self.connect(to: identity, host: "\(host)")
            }
        }
        udpListener = listener
        listener.start(queue: queue)
    }
}
