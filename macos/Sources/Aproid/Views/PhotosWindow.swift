import AppKit
import SwiftUI
import AproidKit

/// The phone's photos and videos, newest first, grouped by month.
struct PhotosWindow: View {
    @ObservedObject var store: PhotosStore

    @State private var size: CGFloat = 132

    var body: some View {
        content
            .frame(minWidth: 640, minHeight: 460)
            .background(Theme.panel)
            .navigationTitle("Photos")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItemGroup {
                    Slider(value: $size, in: 88...220)
                        .frame(width: 110)
                        .help("Thumbnail size")
                    Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .help("Load the newest photos")
                        .disabled(!store.hasPhone)
                    Button { store.download(store.selection) } label: {
                        Label("Download", systemImage: "square.and.arrow.down")
                    }
                    .help("Save the selected photos to Downloads")
                    .disabled(store.selection.isEmpty || !store.hasPhone)
                }
            }
            .onAppear { if store.photos.isEmpty { store.loadMore() } }
    }

    @ViewBuilder
    private var content: some View {
        if store.photos.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: store.hasPhone ? "photo.on.rectangle.angled" : "iphone.slash")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if store.loading { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    private var emptyText: String {
        if !store.hasPhone { return "Connect your phone to see its photos" }
        if store.loading { return "Loading your photos…" }
        return "No photos yet.\nOn your phone, allow Aproid to see photos and videos."
    }

    private var subtitle: String {
        if !store.selection.isEmpty { return "\(store.selection.count) selected" }
        return store.photos.isEmpty ? "" : "\(store.photos.count)\(store.more ? "+" : "") items"
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: size, maximum: size * 1.4), spacing: 4)],
                spacing: 4,
                pinnedViews: [.sectionHeaders]
            ) {
                ForEach(store.months) { month in
                    Section {
                        ForEach(month.photos) { photo in
                            PhotoTile(
                                photo: photo,
                                image: store.thumbnails[photo.id],
                                isSelected: store.selection.contains(photo.id),
                                isDownloading: store.downloading.contains(photo.id)
                            )
                            .onTapGesture(count: 2) { store.download([photo.id]) }
                            .onTapGesture { toggle(photo.id) }
                            .contextMenu {
                                Button("Download to Downloads") { store.download([photo.id]) }
                            }
                            .onAppear { if photo.id == store.photos.last?.id { store.loadMore() } }
                        }
                    } header: {
                        MonthHeader(title: month.title, count: month.photos.count)
                    }
                }

                if store.loading {
                    ProgressView().controlSize(.small).padding()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    /// Click selects one; Command-click adds to the selection.
    private func toggle(_ id: Int64) {
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            if store.selection.contains(id) { store.selection.remove(id) } else { store.selection.insert(id) }
        } else {
            store.selection = store.selection == [id] ? [] : [id]
        }
    }
}

private struct MonthHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .bold))
            Text("\(count)").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// One square thumbnail. Videos show a play badge; a downloading photo shows a spinner.
private struct PhotoTile: View {
    let photo: PhonePhoto
    let image: NSImage?
    let isSelected: Bool
    let isDownloading: Bool

    @State private var hovering = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Theme.thumb.overlay(
                        Image(systemName: photo.isVideo ? "video" : "photo").foregroundStyle(.secondary)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if photo.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isDownloading {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.accent)
                        .font(.system(size: 18))
                        .padding(6)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.accent)
                        .font(.system(size: 18))
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.accent, lineWidth: isSelected ? 3 : 0)
            )
            .brightness(hovering ? 0.05 : 0)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .help("\(photo.name)\n\(PhotosStore.date(photo).formatted(date: .abbreviated, time: .shortened))")
    }
}
