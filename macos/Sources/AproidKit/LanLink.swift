import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import NIOTLS

/// LAN discovery and connection setup from the KDE Connect protocol.
///
/// 1. We broadcast our identity over UDP to port 1716.
/// 2. A peer that hears it opens a TCP connection to our tcpPort and sends its identity.
/// 3. The socket is upgraded to TLS. The side that opened the TCP connection is the TLS server.
/// 4. With protocol v8, both sides send their identity again over TLS.
///
/// Mirrors android/protocol/.../LanLink.kt.
public final class LanLink {
    public typealias LinkCallback = (DeviceLink) -> Void

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    private let identityProvider: () -> DeviceIdentity
    private let trustStore: TrustStore
    private let onLink: LinkCallback
    private let udpPortNumber: UInt16
    private let tcpPorts: ClosedRange<UInt16>
    private let serverContext: NIOSSLContext
    private let clientContext: NIOSSLContext
    private var tcpChannel: Channel?
    private var udpChannel: Channel?

    /// Port the TCP listener is bound to, once started.
    public private(set) var tcpPort: UInt16?

    public init(
        identityProvider: @escaping () -> DeviceIdentity,
        certificate: DeviceCertificate,
        trustStore: TrustStore,
        udpPort: UInt16 = AproidKit.udpPort,
        tcpPorts: ClosedRange<UInt16> = AproidKit.tcpPortRange,
        onLink: @escaping LinkCallback
    ) throws {
        self.identityProvider = identityProvider
        self.trustStore = trustStore
        self.onLink = onLink
        self.udpPortNumber = udpPort
        self.tcpPorts = tcpPorts

        // Every device is self-signed, so the handshake accepts any certificate and
        // LinkHandler checks it afterwards against the device id and the trust store.
        var server = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(certificate.nioCertificate)],
            privateKey: .privateKey(certificate.nioPrivateKey)
        )
        server.certificateVerification = .noHostnameVerification
        serverContext = try NIOSSLContext(configuration: server)

        var client = TLSConfiguration.makeClientConfiguration()
        client.certificateChain = [.certificate(certificate.nioCertificate)]
        client.privateKey = .privateKey(certificate.nioPrivateKey)
        client.certificateVerification = .noHostnameVerification
        clientContext = try NIOSSLContext(configuration: client)
    }

    deinit {
        try? group.syncShutdownGracefully()
    }

    /// Binds the TCP listener and the UDP discovery port. Call off the main thread if you can.
    public func start() throws {
        tcpChannel = try bindTCP()
        tcpPort = tcpChannel?.localAddress?.port.flatMap { UInt16(exactly: $0) }

        // If the port is taken (for example by KDE Connect) we can still be found over TCP.
        udpChannel = try? DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(DiscoveryHandler(link: self))
            }
            .bind(host: "0.0.0.0", port: Int(udpPortNumber))
            .wait()
    }

    public func stop() {
        tcpChannel?.close(promise: nil)
        udpChannel?.close(promise: nil)
        tcpChannel = nil
        udpChannel = nil
        tcpPort = nil
    }

    /// Send our identity to everyone on the local network.
    /// A plain BSD socket keeps this independent of the event loops.
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

    /// Connect to a peer that announced itself. The link arrives through `onLink`.
    @discardableResult
    public func connect(to peer: DeviceIdentity, host: String) -> EventLoopFuture<Void> {
        guard let port = peer.tcpPort else {
            return group.next().makeFailedFuture(ProtocolError("peer did not send tcpPort"))
        }

        return ClientBootstrap(group: group)
            .connectTimeout(.seconds(5))
            .connect(host: host, port: Int(port))
            .flatMapThrowing { channel in
                try self.secureOutgoing(channel, peer: peer, host: host)
            }
    }

    func currentIdentity() -> DeviceIdentity {
        var identity = identityProvider()
        identity.tcpPort = tcpPort

        return identity
    }

    var ownDeviceId: String { identityProvider().deviceId }

    // MARK: Setup

    private func bindTCP() throws -> Channel {
        var lastError: Error = ProtocolError("no free TCP port in \(tcpPorts)")

        for port in tcpPorts {
            do {
                return try ServerBootstrap(group: group)
                    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelInitializer { channel in
                        channel.pipeline.addHandler(PlainIdentityHandler(link: self))
                    }
                    .bind(host: "0.0.0.0", port: Int(port))
                    .wait()
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    /// We opened the connection: send our identity in plain text, then act as TLS server.
    private func secureOutgoing(_ channel: Channel, peer: DeviceIdentity, host: String) throws {
        channel.eventLoop.assertInEventLoop()

        let data = try currentIdentity().toPacket().serialize()
        channel.writeAndFlush(channel.allocator.buffer(bytes: data), promise: nil)

        let box = PeerCertificateBox()
        let tls = NIOSSLServerHandler(context: serverContext, customVerificationCallback: box.verify)
        try addSecureHandlers(channel, tls: tls, box: box, plainIdentity: peer, host: host)
    }

    /// The peer opened the connection and sent its identity: act as TLS client.
    func secureIncoming(_ channel: Channel, plainIdentity: DeviceIdentity) throws {
        let box = PeerCertificateBox()
        let tls = try NIOSSLClientHandler(context: clientContext, serverHostname: nil, customVerificationCallback: box.verify)
        let host = channel.remoteAddress?.ipAddress ?? ""
        try addSecureHandlers(channel, tls: tls, box: box, plainIdentity: plainIdentity, host: host)
    }

    private func addSecureHandlers(
        _ channel: Channel,
        tls: ChannelHandler,
        box: PeerCertificateBox,
        plainIdentity: DeviceIdentity,
        host: String
    ) throws {
        let handler = LinkHandler(link: self, box: box, plainIdentity: plainIdentity, host: host)
        let pipeline = channel.pipeline.syncOperations

        try pipeline.addHandler(tls, position: .first)
        try pipeline.addHandler(ByteToMessageHandler(LineDecoder()))
        try pipeline.addHandler(handler)
    }

    func checkCertificate(_ der: [UInt8], deviceId: String) throws {
        guard DeviceCertificate.commonName(ofDER: der) == deviceId else {
            throw ProtocolError("certificate does not match device id")
        }

        if let trusted = trustStore.certificate(for: deviceId), trusted != der {
            throw ProtocolError("certificate changed for a paired device")
        }
    }

    func linkReady(_ link: DeviceLink) {
        onLink(link)
    }
}

// MARK: - Handlers

/// Captures the peer's certificate during the handshake. Trust is checked after it.
final class PeerCertificateBox {
    var certificate: NIOSSLCertificate?

    func verify(_ chain: [NIOSSLCertificate], _ promise: EventLoopPromise<NIOSSLVerificationResult>) {
        certificate = chain.first
        promise.succeed(chain.isEmpty ? .failed : .certificateVerified)
    }
}

/// Splits incoming bytes into lines.
struct LineDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer

    mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        let view = buffer.readableBytesView
        guard let newline = view.firstIndex(of: 0x0A) else {
            if buffer.readableBytes > 16 * 1024 * 1024 { throw ProtocolError("line too long") }
            return .needMoreData
        }

        let line = buffer.readSlice(length: newline - view.startIndex)!
        buffer.moveReaderIndex(forwardBy: 1)
        context.fireChannelRead(wrapInboundOut(line))

        return .continue
    }

    mutating func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        try decode(context: context, buffer: &buffer)
    }
}

/// Reads the plain-text identity of an incoming connection, then hands over to TLS.
final class PlainIdentityHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer

    private unowned let link: LanLink
    private var buffer: ByteBuffer?

    init(link: LanLink) {
        self.link = link
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var chunk = unwrapInboundIn(data)
        if buffer == nil {
            buffer = chunk
        } else {
            buffer!.writeBuffer(&chunk)
        }

        guard let bytes = buffer?.readableBytesView, let newline = bytes.firstIndex(of: 0x0A) else {
            if (buffer?.readableBytes ?? 0) > 64 * 1024 { context.close(promise: nil) }
            return
        }

        do {
            let line = Array(bytes[bytes.startIndex..<newline])
            let identity = try DeviceIdentity(packet: try NetworkPacket.parse(Data(line)))
            guard identity.deviceId != link.ownDeviceId else { throw ProtocolError("connected to ourselves") }

            context.pipeline.syncOperations.removeHandler(context: context, promise: nil)
            try link.secureIncoming(context.channel, plainIdentity: identity)
        } catch {
            context.close(promise: nil)
        }
    }
}

/// Runs the encrypted part: checks the certificate, swaps v8 identities, then carries packets.
final class LinkHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private enum State {
        case handshaking
        case awaitingIdentity
        case open(DeviceLink)
        case closed
    }

    private unowned let link: LanLink
    private let box: PeerCertificateBox
    private let plainIdentity: DeviceIdentity
    private let host: String
    private var state = State.handshaking
    private var certificateDER: [UInt8] = []
    private var publicKeyDER: [UInt8] = []

    init(link: LanLink, box: PeerCertificateBox, plainIdentity: DeviceIdentity, host: String) {
        self.link = link
        self.box = box
        self.plainIdentity = plainIdentity
        self.host = host
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let tlsEvent = event as? TLSUserEvent, case .handshakeCompleted = tlsEvent else {
            context.fireUserInboundEventTriggered(event)
            return
        }

        do {
            guard let peer = box.certificate else { throw ProtocolError("peer sent no certificate") }

            certificateDER = try peer.toDERBytes()
            publicKeyDER = try peer.extractPublicKey().toSPKIBytes()
            try link.checkCertificate(certificateDER, deviceId: plainIdentity.deviceId)

            if plainIdentity.protocolVersion >= 8 {
                let data = try link.currentIdentity().toPacket().serialize()
                context.writeAndFlush(wrapOutbound(context, data), promise: nil)
                state = .awaitingIdentity
            } else {
                open(context, identity: plainIdentity)
            }
        } catch {
            fail(context)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let line = unwrapInboundIn(data)
        guard line.readableBytes > 0, let packet = try? NetworkPacket.parse(Data(line.readableBytesView)) else { return }

        switch state {
        case .awaitingIdentity:
            guard let identity = try? DeviceIdentity(packet: packet), identity.deviceId == plainIdentity.deviceId else {
                fail(context)
                return
            }
            open(context, identity: identity)
        case .open(let deviceLink):
            deviceLink.deliver(packet)
        case .handshaking, .closed:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if case .open(let deviceLink) = state { deviceLink.closed() }
        state = .closed
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    private func open(_ context: ChannelHandlerContext, identity: DeviceIdentity) {
        let deviceLink = DeviceLink(
            identity: identity,
            certificateDER: certificateDER,
            publicKeyDER: publicKeyDER,
            host: host,
            channel: context.channel
        )
        state = .open(deviceLink)
        link.linkReady(deviceLink)
    }

    private func fail(_ context: ChannelHandlerContext) {
        state = .closed
        context.close(promise: nil)
    }

    private func wrapOutbound(_ context: ChannelHandlerContext, _ data: Data) -> NIOAny {
        NIOAny(context.channel.allocator.buffer(bytes: data))
    }
}

/// Hears identity broadcasts and connects to the sender.
final class DiscoveryHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    private unowned let link: LanLink

    init(link: LanLink) {
        self.link = link
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)

        guard let packet = try? NetworkPacket.parse(Data(envelope.data.readableBytesView)),
              let identity = try? DeviceIdentity(packet: packet),
              identity.deviceId != link.ownDeviceId,
              let host = envelope.remoteAddress.ipAddress
        else { return }

        link.connect(to: identity, host: host)
    }
}
