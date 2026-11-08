import AppKit
import Foundation
import AproidKit

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
        more = true
        loading = false
    }
}
