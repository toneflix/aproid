import AppKit
import Foundation
import FlyyLinkKit

/// One month of photos, as the grid shows it under a heading.
struct PhotoMonth: Identifiable {
    let id: String
    let title: String
    let photos: [PhonePhoto]
}

/// The phone's gallery, loaded a page at a time for the Photos window.
@MainActor
final class PhotosStore: ObservableObject {
    @Published private(set) var photos: [PhonePhoto] = []
    @Published private(set) var thumbnails: [Int64: NSImage] = [:]
    @Published private(set) var loading = false
    @Published private(set) var more = true
    @Published private(set) var hasPhone = false
    @Published private(set) var downloading: Set<Int64> = []
    @Published var selection: Set<Int64> = []

    /// The photo open in the viewer.
    @Published private(set) var viewing: Int64?
    /// Full photos fetched for the viewer, saved in a temporary folder.
    @Published private(set) var previews: [Int64: URL] = [:]
    /// Photos the phone couldn't send for the viewer.
    @Published private(set) var failedPreviews: Set<Int64> = []

    private var requestedPreviews: Set<Int64> = []

    /// Sends a packet to the phone the photos come from. Set by the app model.
    var send: ((NetworkPacket) -> Bool)?

    private var deviceId: String?

    private static let monthFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    var months: [PhotoMonth] {
        var groups: [PhotoMonth] = []
        var current: [PhonePhoto] = []
        var key: String?

        for photo in photos {
            let date = Self.date(photo)
            let components = Calendar.current.dateComponents([.year, .month], from: date)
            let photoKey = "\(components.year ?? 0)-\(components.month ?? 0)"

            if photoKey != key, let key, let first = current.first {
                groups.append(PhotoMonth(id: key, title: Self.monthFormat.string(from: Self.date(first)), photos: current))
                current = []
            }
            key = photoKey
            current.append(photo)
        }
        if let key, let first = current.first {
            groups.append(PhotoMonth(id: key, title: Self.monthFormat.string(from: Self.date(first)), photos: current))
        }

        return groups
    }

    nonisolated static func date(_ photo: PhonePhoto) -> Date {
        Date(timeIntervalSince1970: TimeInterval(photo.date) / 1000)
    }

    /// A phone connected: start over with its gallery the next time the window asks.
    func attach(_ deviceId: String) {
        hasPhone = true
        guard self.deviceId != deviceId else { return }

        self.deviceId = deviceId
        reset()
    }

    func detach(_ deviceId: String) {
        guard self.deviceId == deviceId else { return }

        hasPhone = false
        loading = false
        failedPreviews.formUnion(requestedPreviews)
        requestedPreviews = []
    }

    /// Loads from the newest photo again.
    func refresh() {
        reset()
        loadMore()
    }

    /// Asks for the next, older page. Does nothing while one is on its way.
    func loadMore() {
        guard hasPhone, more, !loading else { return }

        loading = send?(Photos.request(before: photos.last?.date)) == true
    }

    func ingest(_ page: Photos.Page, from deviceId: String) {
        guard deviceId == self.deviceId else { return }

        let known = Set(photos.map(\.id))
        let fresh = page.photos.filter { !known.contains($0.id) }

        for photo in fresh {
            if let data = photo.thumbnail.flatMap({ Data(base64Encoded: $0) }), let image = NSImage(data: data) {
                thumbnails[photo.id] = image
            }
        }

        // Thumbnails live in their own map, so the list stays light.
        photos += fresh.map { (photo: PhonePhoto) -> PhonePhoto in
            var light = photo
            light.thumbnail = nil
            return light
        }
        more = page.more && !fresh.isEmpty
        loading = false
    }

    var viewed: PhonePhoto? {
        viewing.flatMap { id in photos.first { $0.id == id } }
    }

    /// Opens a photo in the viewer and fetches it in full, along with the next one so stepping through is quick.
    func open(_ id: Int64) {
        viewing = id
        selection = [id]
        fetchPreview(id)

        if let next = neighbour(of: id, by: 1), !next.isVideo { fetchPreview(next.id) }
        if let index = photos.firstIndex(where: { $0.id == id }), index >= photos.count - 5 { loadMore() }
    }

    /// Moves the viewer to the previous (-1) or next (1) photo.
    func step(_ offset: Int) {
        guard let id = viewing, let photo = neighbour(of: id, by: offset) else { return }

        open(photo.id)
    }

    func canStep(_ offset: Int) -> Bool {
        viewing.flatMap { neighbour(of: $0, by: offset) } != nil
    }

    func closeViewer() {
        viewing = nil
    }

    func retryPreview(_ id: Int64) {
        failedPreviews.remove(id)
        requestedPreviews.remove(id)
        fetchPreview(id)
    }

    func ingestPreview(_ id: Int64, url: URL?, from deviceId: String) {
        guard deviceId == self.deviceId else { return }

        requestedPreviews.remove(id)
        if let url {
            previews[id] = url
        } else {
            failedPreviews.insert(id)
        }
    }

    private func fetchPreview(_ id: Int64) {
        guard previews[id] == nil, !failedPreviews.contains(id), !requestedPreviews.contains(id) else { return }

        if send?(Photos.download(id: id, preview: true)) == true {
            requestedPreviews.insert(id)
        } else {
            failedPreviews.insert(id)
        }
    }

    private func neighbour(of id: Int64, by offset: Int) -> PhonePhoto? {
        guard let index = photos.firstIndex(where: { $0.id == id }), photos.indices.contains(index + offset) else { return nil }

        return photos[index + offset]
    }

    /// Asks the phone to send these in full. They arrive in Downloads like any shared file.
    func download(_ ids: Set<Int64>) {
        for id in ids.sorted() where !downloading.contains(id) {
            if send?(Photos.download(id: id)) == true { downloading.insert(id) }
        }
    }

    private func reset() {
        photos = []
        thumbnails = [:]
        selection = []
        downloading = []
        viewing = nil
        previews = [:]
        failedPreviews = []
        requestedPreviews = []
        more = true
        loading = false
    }
}
