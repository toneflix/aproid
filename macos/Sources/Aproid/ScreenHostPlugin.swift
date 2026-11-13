import Foundation
import AproidKit

/// Shows this Mac's screen to a paired computer that asks for it ("flyylink.screen.request"), as JPEG pictures.
/// One computer watches at a time. It works the Mac through "flyylink.input", which InputSharePlugin plays.
final class ScreenHostPlugin: Plugin {
    let incoming: Set<String> = [PacketType.screenRequest]

    /// Whether paired computers may see this screen. The same setting that lets them use the keyboard and mouse.
    var allows: () -> Bool = { true }

    /// Called with the computer now watching, or nil.
    var onChange: ((String?) -> Void)?

    private let queue = DispatchQueue(label: "com.toneflix.aproid.screen-host")
    private var share: ScreenShare?

    /// The computer watching this screen now, or nil.
    var viewerId: String? { queue.sync { share?.deviceId } }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let request = Screen.request(packet), device.link.identity.deviceType.isComputer else { return }

        queue.async { [self] in
            switch request.action {
            case .start:
                start(for: device, maxSize: Int(request.maxSize))
            case .stop:
                if share?.deviceId == device.id { end() }
            }
        }
    }

    /// Stops showing the screen to `deviceId`, or to anyone when nil.
    func stop(_ deviceId: String? = nil) {
        queue.async { [self] in
            if deviceId == nil || share?.deviceId == deviceId { end() }
        }
    }

    private func start(for device: Device, maxSize: Int) {
        end()

        guard allows() else {
            device.send(Screen.stopped())
            return
        }
        guard ScreenCapture.hasAccess else {
            ScreenCapture.requestAccess()
            device.send(Screen.stopped())
            return
        }

        let share = ScreenShare(deviceId: device.id)
        share.onEnd = { [weak self, weak share] in
            self?.queue.async {
                guard let self, let share, self.share === share else { return }

                self.share = nil
                self.onChange?(nil)
            }
        }
        self.share = share
        share.start(on: device, maxSize: maxSize)
        onChange?(device.id)
    }

    private func end() {
        guard let share else { return }

        self.share = nil
        share.stop()
        onChange?(nil)
    }
}

/// One computer watching this screen: each new picture goes out on a live stream to it.
private final class ScreenShare {
    let deviceId: String

    /// Called once when the share ends by itself: the viewer left, or capture stopped.
    var onEnd: (() -> Void)?

    private let capture = ScreenCapture()
    private let stream = PayloadStream()
    private let lock = NSLock()
    private let startedAt = DispatchTime.now()
    private var last: Data?
    private var stopped = false

    init(deviceId: String) {
        self.deviceId = deviceId
    }

    func start(on device: Device, maxSize: Int) {
        capture.onPicture = { [weak self] jpeg in self?.send(jpeg) }
        capture.onStop = { [weak self] _ in self?.stream.close() }
        // The screen may be still, so the viewer gets the last picture as soon as it connects.
        stream.onOpen = { [weak self] in self?.sendLast() }
        stream.onClose = { [weak self] _ in
            self?.capture.stop()
            self?.onEnd?()
        }

        capture.start(maxSize: maxSize) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let size):
                guard !self.lock.withLock({ self.stopped }) else {
                    self.capture.stop()
                    return
                }

                let packet = Screen.started(width: Int64(size.width), height: Int64(size.height), codec: Screen.jpeg, platform: RemoteInput.macOS)
                device.sendStream(packet, stream: self.stream)
            case .failure:
                device.send(Screen.stopped())
                self.onEnd?()
            }
        }
    }

    func stop() {
        lock.withLock { stopped = true }
        stream.close()
        capture.stop()
    }

    private func send(_ jpeg: Data) {
        let piece = Self.piece(jpeg, at: startedAt)
        lock.withLock { last = jpeg }
        stream.write(piece)
    }

    private func sendLast() {
        guard let jpeg = lock.withLock({ last }) else { return }

        stream.write(Self.piece(jpeg, at: startedAt))
    }

    private static func piece(_ jpeg: Data, at start: DispatchTime) -> Data {
        let micros = Int64((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1000)
        let frame = ScreenFrame(data: jpeg, timeUs: micros, flags: ScreenFrame.key)

        return frame.header() + frame.data
    }
}
