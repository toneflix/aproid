import Foundation
import AproidKit

/// Lets paired devices see and control what this Mac is playing ("kdeconnect.mpris.request").
final class MediaHostPlugin: Plugin {
    let incoming: Set<String> = [PacketType.mprisRequest]

    private let devices: DeviceRegistry
    private let media = LocalMedia()
    private let queue = DispatchQueue(label: "com.toneflix.aproid.media-host")
    private var lastSent: [MediaPlayer] = []

    init(devices: DeviceRegistry) {
        self.devices = devices
        media.onChange = { [weak self] in self?.queue.async { self?.broadcast() } }
        media.start()
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let request = MediaRequest(packet: packet) else { return }

        queue.async { [media] in
            let changes = request.action != nil || request.seekTo != nil || request.volume != nil
            if changes { media.perform(request) }

            let players = media.players()
            if request.wantsPlayerList {
                device.send(Media.playerListPacket(players.map(\.name)))
            }
            if request.wantsNowPlaying || changes, let player = players.first(where: { $0.name == request.player }) {
                device.send(player.toPacket())
            }
        }
    }

    /// Tells every paired device about a change, once per change.
    private func broadcast() {
        let players = media.players()
        guard players != lastSent else { return }

        let namesChanged = players.map(\.name) != lastSent.map(\.name)
        lastSent = players

        for device in devices.all where device.isPaired && device.link.identity.incomingCapabilities.contains(PacketType.mpris) {
            if namesChanged { device.send(Media.playerListPacket(players.map(\.name))) }
            players.forEach { device.send($0.toPacket()) }
        }
    }
}
