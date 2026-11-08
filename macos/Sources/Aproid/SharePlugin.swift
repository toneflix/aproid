import AppKit
import AproidKit

/// Moves files, links and text between the Mac and the phone. Files go to Downloads, links open in the
/// browser, and text lands on the clipboard. A file that stops halfway resumes when the phone reconnects.
final class SharePlugin: Plugin {
    let incoming: Set<String> = [PacketType.shareRequest, PacketType.shareResume]

    /// Called with each new or updated Recent entry, on any thread.
    var onActivity: ((Activity) -> Void)?

    /// Called when a file has arrived, to tell the user.
    var onFileReceived: ((URL, Device) -> Void)?

    /// A file we offered, kept for a while so the phone can ask for the rest.
    private struct Outgoing {
        let url: URL
        let deviceId: String
        let activity: Activity
        let expires: Date
    }

    /// A file that stopped arriving, waiting for the phone to come back.
    private struct Incoming {
        let url: URL
        let deviceId: String
        let activity: Activity
        let total: Int64
    }

    private static let keepOffers: TimeInterval = 30 * 60

    private let folder: URL
    private let files = FileManager.default
    private let lock = NSLock()
    private var outgoing: [String: Outgoing] = [:]
    private var paused: [String: Incoming] = [:]

    init(folder: URL) {
        self.folder = folder
    }

    func onPaired(_ device: Device) {
        let waiting = lock.withLock { paused.filter { $0.value.deviceId == device.id } }

        for (id, file) in waiting {
            let have = (try? files.attributesOfItem(atPath: file.url.path)[.size] as? NSNumber)?.int64Value ?? 0
            device.send(Share.resumePacket(transferId: id, offset: have))
        }
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        if let request = Share.resumeRequest(packet) {
            resume(request.transferId, from: request.offset, to: device)
            return
        }

        guard let share = Share(packet: packet) else { return }

        switch share {
        case let .file(name, size, transferId, offset): receive(packet, name: name, size: size, transferId: transferId, offset: offset, from: device)
        case .link(let link): open(link, from: device)
        case .text(let text): paste(text, from: device)
        }
    }

    // MARK: Sending

    /// Offers a file to the phone. Call off the main thread.
    func send(_ url: URL, to device: Device) {
        let id = UUID().uuidString
        let activity = Activity(.sending, title: url.lastPathComponent, detail: "Sending to \(device.name)")
        onActivity?(activity)

        lock.withLock {
            outgoing = outgoing.filter { $0.value.expires > Date() }
            outgoing[id] = Outgoing(url: url, deviceId: device.id, activity: activity, expires: Date().addingTimeInterval(Self.keepOffers))
        }

        offer(url, id: id, from: 0, to: device, activity: activity)
    }

    private func resume(_ id: String, from offset: Int64, to device: Device) {
        guard let file = lock.withLock({ outgoing[id] }), file.deviceId == device.id else { return }

        var activity = file.activity
        activity.kind = .sending
        activity.detail = "Resuming to \(device.name)"
        onActivity?(activity)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            offer(file.url, id: id, from: offset, to: device, activity: activity)
        }
    }

    private func offer(_ url: URL, id: String, from offset: Int64, to device: Device, activity: Activity) {
        let finish: (Error?) -> Void = { [weak self] error in
            var done = activity
            done.date = Date()
            done.kind = error == nil ? .sent : .failed
            done.detail = error == nil ? "Sent to \(device.name)" : "Stopped · resumes when \(device.name) reconnects"
            if error == nil { self?.lock.withLock { _ = self?.outgoing.removeValue(forKey: id) } }
            self?.onActivity?(done)
        }

        guard device.isPaired,
              let attributes = try? files.attributesOfItem(atPath: url.path),
              let source = try? FileHandle(forReadingFrom: url)
        else {
            finish(ProtocolError("could not open \(url.lastPathComponent)"))
            return
        }

        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let start = min(max(offset, 0), size)
        let modified = (attributes[.modificationDate] as? Date).map { Int64($0.timeIntervalSince1970 * 1000) }
        let packet = Share.filePacket(name: url.lastPathComponent, size: size, lastModifiedMillis: modified, transferId: id, offset: start)

        do {
            try source.seek(toOffset: UInt64(start))
        } catch {
            try? source.close()
            finish(error)
            return
        }

        // On failure it calls the completion itself.
        device.sendWithPayload(packet, size: size - start, source: source) { error in
            try? source.close()
            finish(error)
        }
    }

    // MARK: Receiving

    private func receive(_ packet: NetworkPacket, name: String, size: Int64, transferId: String?, offset: Int64, from device: Device) {
        let resumed = transferId.flatMap { id in lock.withLock { paused.removeValue(forKey: id) } }
        let total = resumed?.total ?? offset + size

        let target = resumed.flatMap { openForAppend($0.url, at: offset) } ?? (offset == 0 ? reserveFile(Share.safeName(name)) : nil)
        guard let target else {
            onActivity?(Activity(.failed, title: name, detail: "Could not save to Downloads"))
            return
        }

        let (url, sink) = target
        var activity = resumed?.activity ?? Activity(.receiving, title: url.lastPathComponent, detail: "")
        activity.kind = .receiving
        activity.detail = "\(resumed == nil ? "Receiving" : "Resuming") \(Bytes.text(total)) from \(device.name)"
        let started = activity
        onActivity?(started)

        let finish: (Error?) -> Void = { [weak self] error in
            try? sink.close()
            guard let self else { return }

            var done = started
            done.date = Date()

            if error == nil {
                done.kind = .received(url)
                done.detail = "Received · \(Bytes.text(total))"
                onFileReceived?(url, device)
            } else if let transferId {
                // Keep what arrived; the rest comes when the phone reconnects.
                lock.withLock { paused[transferId] = Incoming(url: url, deviceId: device.id, activity: done, total: total) }
                done.kind = .failed
                done.detail = "Paused · resumes when \(device.name) reconnects"
            } else {
                try? files.removeItem(at: url)
                done.kind = .failed
                done.detail = "Transfer from \(device.name) stopped"
            }

            onActivity?(done)
        }

        do {
            try device.receivePayload(packet, into: sink).whenComplete { result in
                if case .failure(let error) = result { finish(error) } else { finish(nil) }
            }
        } catch {
            finish(error)
        }
    }

    /// Opens a partly received file to add the rest, if it is as long as the sender thinks.
    private func openForAppend(_ url: URL, at offset: Int64) -> (URL, FileHandle)? {
        guard let handle = try? FileHandle(forWritingTo: url),
              let end = try? handle.seekToEnd(), end == UInt64(offset)
        else { return nil }

        return (url, handle)
    }

    /// Creates an empty file with a name not taken yet, such as "photo (2).jpg".
    private func reserveFile(_ name: String) -> (URL, FileHandle)? {
        lock.withLock {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var url = folder.appendingPathComponent(name)
            var copy = 1

            while files.fileExists(atPath: url.path) {
                copy += 1
                let numbered = "\(base) (\(copy))"
                url = folder.appendingPathComponent(ext.isEmpty ? numbered : "\(numbered).\(ext)")
            }

            guard files.createFile(atPath: url.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: url)
            else { return nil }

            return (url, handle)
        }
    }

    // MARK: Links and text

    private func open(_ link: String, from device: Device) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased()) else {
            // Anything but a web link could launch an app, so only offer it as text.
            paste(link, from: device)
            return
        }

        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        onActivity?(Activity(.link(url), title: url.host ?? link, detail: "Opened from \(device.name)"))
    }

    private func paste(_ text: String, from device: Device) {
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        let preview = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        onActivity?(Activity(.text, title: "“\(preview)”", detail: "Copied from \(device.name)"))
    }
}
