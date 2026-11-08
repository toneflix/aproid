import AppKit
import SwiftUI
import AproidKit

/// Receives the phone's screen stream ("aproid.screen") and feeds it to the decoder.
final class ScreenPlugin: Plugin {
    let incoming: Set<String> = [PacketType.screen]

    let decoder: ScreenDecoder

    /// Called on a network thread when a phone starts or stops streaming.
    var onStarted: ((Device) -> Void)?
    var onEnded: ((String) -> Void)?

    init(decoder: ScreenDecoder) {
        self.decoder = decoder
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let info = Screen.info(packet) else { return }

        guard info.running, packet.payloadSize == Screen.stream else {
            onEnded?(device.id)
            return
        }

        decoder.reset()
        let reader = ScreenFrameReader()
        let decoder = decoder
        let deviceId = device.id

        do {
            try device.receiveStream(packet) { data in
                for frame in try reader.feed(data) { decoder.decode(frame) }
            }
            .whenComplete { [weak self] _ in self?.onEnded?(deviceId) }

            onStarted?(device)
        } catch {
            onEnded?(deviceId)
        }
    }
}

/// The state of mirroring, for the screen window.
@MainActor
final class ScreenMirror: ObservableObject {
    enum Phase: Equatable {
        case idle
        case waiting
        case live
        case ended
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var videoSize = CGSize.zero
    @Published private(set) var deviceName = ""

    let decoder = ScreenDecoder()

    /// Sends a packet to a phone. Set by the app model.
    var send: ((String, NetworkPacket) -> Bool)?

    private(set) var deviceId: String?

    init() {
        decoder.onSize = { [weak self] size in Task { @MainActor in self?.videoSize = size } }
    }

    /// Asks the phone to start; it shows a prompt the user has to allow.
    func begin(deviceId: String, name: String) {
        if phase == .live, self.deviceId == deviceId { return }

        if let old = self.deviceId, old != deviceId { _ = send?(old, Screen.stop()) }
        self.deviceId = deviceId
        deviceName = name
        phase = send?(deviceId, Screen.start()) == true ? .waiting : .ended
    }

    func stop() {
        guard let deviceId else { return }

        _ = send?(deviceId, Screen.stop())
        self.deviceId = nil
        phase = .idle
        decoder.reset()
    }

    func input(_ input: ScreenInput) {
        guard phase == .live, let deviceId else { return }

        _ = send?(deviceId, input.toPacket())
    }

    /// A stream arrived, whether the Mac asked for it or the user started it on the phone.
    func started(deviceId: String, name: String) {
        if let old = self.deviceId, old != deviceId { _ = send?(old, Screen.stop()) }

        self.deviceId = deviceId
        deviceName = name
        phase = .live
    }

    func ended(deviceId: String) {
        guard deviceId == self.deviceId, phase != .idle else { return }

        phase = .ended
    }
}

/// The window that shows the phone's screen. An AppKit window, so it can open when the phone starts
/// mirroring by itself and keep the phone's shape while resized.
@MainActor
final class ScreenWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let mirror: ScreenMirror

    init(mirror: ScreenMirror) {
        self.mirror = mirror
    }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 820),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Phone screen"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: ScreenWindow(mirror: mirror))
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("PhoneScreen")
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    /// Keeps the window the shape of the phone's picture.
    func fit(_ size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }

        window.contentAspectRatio = size
        var frame = window.frame
        let height = frame.height
        frame.size.width = (height * size.width / size.height).rounded()
        window.setFrame(frame, display: true, animate: true)
    }

    func windowWillClose(_ notification: Notification) {
        mirror.stop()
        window = nil
    }
}
