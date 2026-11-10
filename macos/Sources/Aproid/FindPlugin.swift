import AppKit
import AproidKit

/// Rings this Mac when a paired device asks to find it ("kdeconnect.findmyphone.request"), until someone answers the alert.
final class FindPlugin: Plugin {
    let incoming: Set<String> = [PacketType.findMyPhone]

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        let name = device.name

        Task { @MainActor in Self.ring(from: name) }
    }

    @MainActor private static var ringing: NSSound?

    @MainActor private static func ring(from name: String) {
        guard ringing == nil else { return }

        let sound = NSSound(named: "Sosumi") ?? NSSound(named: "Glass")
        sound?.loops = true
        sound?.volume = 1
        sound?.play()
        ringing = sound

        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Here I am"
        alert.informativeText = "\(name) is looking for this Mac."
        alert.addButton(withTitle: "Found it")
        alert.window.level = .floating
        alert.runModal()

        ringing?.stop()
        ringing = nil
    }
}
