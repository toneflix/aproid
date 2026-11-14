import AppKit
import SwiftUI
import FlyyLinkKit

/// What the phone is playing, with its cover and controls.
struct NowPlayingCard: View {
    let deviceId: String
    let media: NowPlaying
    @ObservedObject var model: AppModel

    private var player: MediaPlayer { media.player }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Artwork(url: media.artwork)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text([player.artist, player.name].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    ControlButton(icon: .skipBack, enabled: player.canGoPrevious) { model.media(deviceId, player.name, .previous) }
                    ControlButton(icon: player.isPlaying ? .pause : .play, size: 17, enabled: player.canPlay || player.canPause) {
                        model.media(deviceId, player.name, .playPause)
                    }
                    ControlButton(icon: .skipForward, enabled: player.canGoNext) { model.media(deviceId, player.name, .next) }
                }
            }

            if player.length > 0 {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    ProgressTrack(
                        fraction: Double(media.position(at: context.date)) / Double(player.length),
                        canSeek: player.canSeek
                    ) { fraction in
                        model.seek(deviceId, player.name, to: Int64(fraction * Double(player.length)))
                    }
                }
            }
        }
        .card(padding: 12)
    }
}

private struct Artwork: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Theme.tint.overlay(Image(lucide: .music, size: 18).foregroundStyle(Theme.accent))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct ControlButton: View {
    let icon: Lucide
    var size: CGFloat = 13
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(lucide: icon, size: size, weight: .semibold)
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovering ? Theme.tint : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

/// A thin bar; click or drag on it to seek when the player allows.
struct ProgressTrack: View {
    let fraction: Double
    let canSeek: Bool
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(Theme.accent).frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    guard canSeek, geometry.size.width > 0 else { return }
                    seek(min(max(value.location.x / geometry.size.width, 0), 1))
                }
            )
        }
        .frame(height: 4)
        .padding(.vertical, 3)
    }
}
