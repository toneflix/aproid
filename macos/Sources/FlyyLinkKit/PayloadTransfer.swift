import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import NIOTLS

/// Moves a packet's payload, such as a file, over its own TLS connection, as KDE Connect does.
/// The sender opens a port and acts as the TLS server; the receiver connects as the client.
/// Each side checks the other's certificate against the one from the device link. Mirrors PayloadTransfer.kt.
public final class PayloadTransfer {
    private static let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)

    private let serverContext: NIOSSLContext
    private let clientContext: NIOSSLContext
    private let ports: ClosedRange<UInt16>

    public init(certificate: DeviceCertificate, ports: ClosedRange<UInt16> = FlyyLinkKit.payloadPortRange) throws {
        self.ports = ports

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

    /// Opens a port and streams `source` to the first peer that connects with `peerCertificateDER`.
    /// `onProgress` gets each piece's byte count once it is written.
    /// Returns the port to put in the packet. Blocks briefly, so call it off the event loops.
    public func offer(
        peerCertificateDER: [UInt8],
        source: FileHandle,
        onProgress: ((Int64) -> Void)? = nil,
        completion: @escaping (Error?) -> Void = { _ in }
    ) throws -> UInt16 {
        let done = Once(completion)
        let serverContext = serverContext
        var lastError: Error = ProtocolError("no free payload port in \(ports)")

        for port in ports {
            do {
                let channel = try ServerBootstrap(group: Self.group)
                    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelInitializer { child in
                        let box = PeerCertificateBox()
                        let tls = NIOSSLServerHandler(context: serverContext, customVerificationCallback: box.verify)
                        let upload = UploadHandler(
                            box: box,
                            expected: peerCertificateDER,
                            source: source,
                            onProgress: onProgress,
                            done: done
                        )

                        return child.pipeline.addHandlers([tls, upload])
                    }
                    .bind(host: "0.0.0.0", port: Int(port))
                    .wait()

                // Nobody came to download it.
                channel.eventLoop.scheduleTask(in: .seconds(60)) {
                    channel.close(promise: nil)
                    done.call(ProtocolError("the peer never downloaded the payload"))
                }

                return port
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    /// Opens a port for a live `stream` that the first peer connecting with `peerCertificateDER` reads until
    /// either side closes it. Returns the port to put in the packet. Blocks briefly, so call it off the event loops.
    public func offer(peerCertificateDER: [UInt8], stream: PayloadStream) throws -> UInt16 {
        let done = Once { stream.finished($0) }
        let serverContext = serverContext
        var lastError: Error = ProtocolError("no free payload port in \(ports)")

        for port in ports {
            do {
                let channel = try ServerBootstrap(group: Self.group)
                    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelInitializer { child in
                        let box = PeerCertificateBox()
                        let tls = NIOSSLServerHandler(context: serverContext, customVerificationCallback: box.verify)
                        let upload = StreamUploadHandler(box: box, expected: peerCertificateDER, stream: stream, done: done)

                        return child.pipeline.addHandlers([tls, upload])
                    }
                    .bind(host: "0.0.0.0", port: Int(port))
                    .wait()

                channel.eventLoop.scheduleTask(in: .seconds(60)) {
                    channel.close(promise: nil)
                    if !stream.isOpen { done.call(ProtocolError("the peer never opened the stream")) }
                }

                return port
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    /// Downloads `size` bytes that the peer offered at `host`:`port` into `sink`.
    /// `onProgress` gets each piece's byte count once it is written.
    public func receive(
        host: String,
        port: UInt16,
        size: Int64,
        peerCertificateDER: [UInt8],
        into sink: FileHandle,
        onProgress: ((Int64) -> Void)? = nil
    ) -> EventLoopFuture<Void> {
        download(host: host, port: port, size: size, peerCertificateDER: peerCertificateDER) { data in
            try sink.write(contentsOf: data)
            onProgress?(Int64(data.count))
        } finish: {
            try? sink.synchronize()
        }
    }

    /// Reads a live stream (payload size `Screen.stream`) and hands each piece to `onData` on a network thread,
    /// until the peer closes it.
    public func stream(
        host: String,
        port: UInt16,
        peerCertificateDER: [UInt8],
        onData: @escaping (Data) throws -> Void
    ) -> EventLoopFuture<Void> {
        download(host: host, port: port, size: Screen.stream, peerCertificateDER: peerCertificateDER, write: onData) {}
    }

    private func download(
        host: String,
        port: UInt16,
        size: Int64,
        peerCertificateDER: [UInt8],
        write: @escaping (Data) throws -> Void,
        finish: @escaping () -> Void
    ) -> EventLoopFuture<Void> {
        let promise = Self.group.next().makePromise(of: Void.self)
        let clientContext = clientContext

        ClientBootstrap(group: Self.group)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                do {
                    let box = PeerCertificateBox()
                    let tls = try NIOSSLClientHandler(context: clientContext, serverHostname: nil, customVerificationCallback: box.verify)
                    let download = DownloadHandler(
                        box: box,
                        expected: peerCertificateDER,
                        size: size,
                        write: write,
                        onFinish: finish,
                        promise: promise
                    )

                    return channel.pipeline.addHandlers([tls, download])
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .connect(host: host, port: Int(port))
            .whenFailure { promise.fail($0) }

        return promise.futureResult
    }
}

/// Calls a completion at most once, from any thread.
private final class Once: @unchecked Sendable {
    private var completion: ((Error?) -> Void)?
    private let lock = NSLock()

    init(_ completion: @escaping (Error?) -> Void) {
        self.completion = completion
    }

    func call(_ error: Error?) {
        let completion = lock.withLock { () -> ((Error?) -> Void)? in
            defer { self.completion = nil }
            return self.completion
        }
        completion?(error)
    }
}

/// Sends a file to the peer once TLS is up and its certificate checks out.
private final class UploadHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    // Large reads keep a fast Wi-Fi link full instead of waiting on small writes.
    private static let chunkSize = 256 * 1024

    private let box: PeerCertificateBox
    private let expected: [UInt8]
    private let source: FileHandle
    private let onProgress: ((Int64) -> Void)?
    private let done: Once

    init(box: PeerCertificateBox, expected: [UInt8], source: FileHandle, onProgress: ((Int64) -> Void)?, done: Once) {
        self.box = box
        self.expected = expected
        self.source = source
        self.onProgress = onProgress
        self.done = done
    }

    func channelActive(context: ChannelHandlerContext) {
        // One download per offer: stop listening once the peer is here.
        context.channel.parent?.close(promise: nil)
        context.fireChannelActive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let tlsEvent = event as? TLSUserEvent, case .handshakeCompleted = tlsEvent else {
            context.fireUserInboundEventTriggered(event)
            return
        }

        guard let der = try? box.certificate(context)?.toDERBytes(), der == expected else {
            fail(context, ProtocolError("payload peer is not the paired device"))
            return
        }

        sendNext(context)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(context, error)
    }

    private func sendNext(_ context: ChannelHandlerContext) {
        let data: Data
        do {
            data = try source.read(upToCount: Self.chunkSize) ?? Data()
        } catch {
            fail(context, error)
            return
        }

        if data.isEmpty {
            try? source.close()
            context.close(promise: nil)
            done.call(nil)
            return
        }

        let buffer = context.channel.allocator.buffer(bytes: data)
        context.writeAndFlush(wrapOutboundOut(buffer)).whenComplete { result in
            switch result {
            case .success:
                self.onProgress?(Int64(data.count))
                // Hop through the event loop so a large file doesn't grow the stack.
                context.eventLoop.execute { self.sendNext(context) }
            case .failure(let error):
                self.fail(context, error)
            }
        }
    }

    private func fail(_ context: ChannelHandlerContext, _ error: Error) {
        try? source.close()
        context.close(promise: nil)
        done.call(error)
    }
}

/// A payload written while it is sent, such as a shared screen. Offer it with `Device.sendStream`, then `write`
/// whole pieces to it and `close` it at the end. While the peer is still busy with earlier pieces, new ones are
/// dropped, so each piece must stand on its own. Mirrors LiveStream.cs.
public final class PayloadStream: @unchecked Sendable {
    private let lock = NSLock()
    private var channel: Channel?
    private var closed = false

    /// Called on a network thread once the peer connects.
    public var onOpen: (() -> Void)?

    /// Called once on a network thread when the stream ends, with the error if it broke.
    public var onClose: ((Error?) -> Void)?

    public init() {}

    /// True while the peer is connected and reading.
    public var isOpen: Bool { lock.withLock { channel != nil && !closed } }

    /// Sends one whole piece. Returns false when it was dropped, because the peer isn't there yet or is busy.
    @discardableResult
    public func write(_ data: Data) -> Bool {
        guard let channel = lock.withLock({ closed ? nil : channel }), channel.isWritable else { return false }

        channel.writeAndFlush(channel.allocator.buffer(bytes: data), promise: nil)
        return true
    }

    /// Ends the stream once what was written has gone out; the peer then sees it close.
    public func close() {
        let channel = lock.withLock { () -> Channel? in
            closed = true
            return self.channel
        }
        guard let channel else { return }

        // Writes finish in order, so this empty one completes after the last piece.
        channel.writeAndFlush(channel.allocator.buffer(capacity: 0)).whenComplete { _ in
            channel.close(promise: nil)
        }
    }

    func opened(_ channel: Channel) {
        let wasClosed = lock.withLock { () -> Bool in
            if !closed { self.channel = channel }
            return closed
        }

        if wasClosed {
            channel.close(promise: nil)
            return
        }
        onOpen?()
    }

    func finished(_ error: Error?) {
        lock.withLock {
            closed = true
            channel = nil
        }
        onClose?(error)
    }
}

/// Hands a live stream's channel to its `PayloadStream` once TLS is up and the peer's certificate checks out.
private final class StreamUploadHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let box: PeerCertificateBox
    private let expected: [UInt8]
    private let stream: PayloadStream
    private let done: Once

    init(box: PeerCertificateBox, expected: [UInt8], stream: PayloadStream, done: Once) {
        self.box = box
        self.expected = expected
        self.stream = stream
        self.done = done
    }

    func channelActive(context: ChannelHandlerContext) {
        context.channel.parent?.close(promise: nil)
        context.fireChannelActive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let tlsEvent = event as? TLSUserEvent, case .handshakeCompleted = tlsEvent else {
            context.fireUserInboundEventTriggered(event)
            return
        }

        guard let der = try? box.certificate(context)?.toDERBytes(), der == expected else {
            context.close(promise: nil)
            done.call(ProtocolError("payload peer is not the paired device"))
            return
        }

        stream.opened(context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        done.call(nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
        done.call(error)
    }
}

/// Hands the incoming bytes on until the announced size has arrived, or, for a live stream, until the peer closes it.
private final class DownloadHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let box: PeerCertificateBox
    private let expected: [UInt8]
    private let size: Int64
    private let write: (Data) throws -> Void
    private let onFinish: () -> Void
    private let promise: EventLoopPromise<Void>
    private var received: Int64 = 0
    private var finished = false

    private var isStream: Bool { size == Screen.stream }

    init(
        box: PeerCertificateBox,
        expected: [UInt8],
        size: Int64,
        write: @escaping (Data) throws -> Void,
        onFinish: @escaping () -> Void,
        promise: EventLoopPromise<Void>
    ) {
        self.box = box
        self.expected = expected
        self.size = size
        self.write = write
        self.onFinish = onFinish
        self.promise = promise
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let tlsEvent = event as? TLSUserEvent, case .handshakeCompleted = tlsEvent else {
            context.fireUserInboundEventTriggered(event)
            return
        }

        guard let der = try? box.certificate(context)?.toDERBytes(), der == expected else {
            finish(context, ProtocolError("payload peer is not the paired device"))
            return
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !finished else { return }

        let buffer = unwrapInboundIn(data)
        let wanted = isStream ? buffer.readableBytes : Int(min(Int64(buffer.readableBytes), size - received))

        do {
            try write(Data(buffer.readableBytesView.prefix(wanted)))
        } catch {
            finish(context, error)
            return
        }

        received += Int64(wanted)
        if !isStream, received >= size { finish(context, nil) }
    }

    func channelInactive(context: ChannelHandlerContext) {
        finish(context, isStream ? nil : ProtocolError("payload ended after \(received) of \(size) bytes"))
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        finish(context, error)
    }

    private func finish(_ context: ChannelHandlerContext, _ error: Error?) {
        guard !finished else { return }

        finished = true
        onFinish()
        context.close(promise: nil)

        if let error { promise.fail(error) } else { promise.succeed(()) }
    }
}
