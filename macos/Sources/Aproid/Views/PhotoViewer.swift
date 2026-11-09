import AVKit
import AppKit
import SwiftUI
import AproidKit

/// A full-window look at one photo or video, with arrows to step through the gallery.
/// The thumbnail shows, enlarged, until the full photo arrives from the phone.
struct PhotoViewer: View {
    @ObservedObject var store: PhotosStore
    let photo: PhonePhoto

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()

            PreviewMedia(
                photo: photo,
                url: store.previews[photo.id],
                thumbnail: store.thumbnails[photo.id],
                failed: store.failedPreviews.contains(photo.id),
                retry: { store.retryPreview(photo.id) }
            )
            .id(photo.id)
            .padding(.horizontal, 64)
            .padding(.vertical, 56)

            HStack {
                StepButton(symbol: "chevron.left", key: .leftArrow, help: "Previous") { store.step(-1) }
                    .disabled(!store.canStep(-1))
                Spacer()
                StepButton(symbol: "chevron.right", key: .rightArrow, help: "Next") { store.step(1) }
                    .disabled(!store.canStep(1))
            }
            .padding(.horizontal, 14)
        }
        .overlay(alignment: .top) { topBar }
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { store.closeViewer() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(ViewerButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")

            VStack(alignment: .leading, spacing: 1) {
                Text(photo.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(PhotosStore.date(photo).formatted(date: .long, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.downloading.contains(photo.id) {
                ProgressView().controlSize(.small)
            }
            Button { store.download([photo.id]) } label: {
                Label("Download", systemImage: "square.and.arrow.down").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(ViewerButtonStyle())
            .disabled(store.downloading.contains(photo.id) || !store.hasPhone)
            .help("Save to Downloads")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

/// The photo or video itself, or its thumbnail while the full one is on its way.
private struct PreviewMedia: View {
    let photo: PhonePhoto
    let url: URL?
    let thumbnail: NSImage?
    let failed: Bool
    let retry: () -> Void

    var body: some View {
        if let url, photo.isVideo {
            VideoPreview(url: url)
        } else if let url {
            ImagePreview(url: url, placeholder: thumbnail)
        } else {
            waiting
        }
    }

    private var waiting: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .blur(radius: failed ? 0 : 6)
                    .opacity(0.8)
            }

            VStack(spacing: 10) {
                if failed {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 26, weight: .light))
                    Text("Couldn't get this \(photo.isVideo ? "video" : "photo") from your phone").font(.callout)
                    Button("Try again", action: retry).controlSize(.small)
                } else {
                    ProgressView()
                    Text(photo.isVideo ? "Loading video…" : "Loading photo…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// A full-size photo that zooms with a pinch or a double-click, and pans while zoomed.
private struct ImagePreview: View {
    let url: URL
    let placeholder: NSImage?

    @State private var image: NSImage?
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        Group {
            if let shown = image ?? placeholder {
                Image(nsImage: shown)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .offset(offset)
                    .gesture(magnify.simultaneously(with: pan))
                    .onTapGesture(count: 2) { toggleZoom() }
            }
        }
        .task(id: url) { image = await Self.load(url) }
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { zoom = min(max(baseZoom * $0, 1), 6) }
            .onEnded { _ in
                baseZoom = zoom
                if zoom == 1 { recenter() }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                offset = CGSize(width: baseOffset.width + value.translation.width, height: baseOffset.height + value.translation.height)
            }
            .onEnded { _ in baseOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            zoom = zoom > 1 ? 1 : 2.5
            baseZoom = zoom
            if zoom == 1 { recenter() }
        }
    }

    private func recenter() {
        offset = .zero
        baseOffset = .zero
    }

    private static func load(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
    }
}

/// Plays a video with the standard macOS controls.
private struct VideoPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true

        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard (view.player?.currentItem?.asset as? AVURLAsset)?.url != url else { return }

        view.player?.pause()
        view.player = AVPlayer(url: url)
        view.player?.play()
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
    }
}

private struct StepButton: View {
    let symbol: String
    let key: KeyEquivalent
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .help(help)
    }
}

private struct ViewerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }
}
