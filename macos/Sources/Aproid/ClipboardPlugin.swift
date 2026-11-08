import AppKit
import AproidKit

/// Shares copied text with paired phones, and puts text from the phone on the Mac clipboard.
final class ClipboardPlugin: Plugin {
    let incoming: Set<String> = [PacketType.clipboard, PacketType.clipboardConnect]

    private let devices: DeviceRegistry
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    init(devices: DeviceRegistry) {
        self.devices = devices
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// macOS has no clipboard change event, so check once a second. Call on the main thread.
    func startWatching() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func onPaired(_ device: Device) {
        DispatchQueue.main.async { [self] in
            guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            device.send(Clipboard.connectPacket(text, timestampMillis: now))
        }
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let text = Clipboard.content(packet) else { return }

        DispatchQueue.main.async { [self] in
            guard pasteboard.string(forType: .string) != text else { return }

            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            // Our own write must not be sent back to the phone.
            lastChangeCount = pasteboard.changeCount
        }
    }

    private func check() {
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }

        devices.all.filter(\.isPaired).forEach { $0.send(Clipboard.packet(text)) }
    }
}
