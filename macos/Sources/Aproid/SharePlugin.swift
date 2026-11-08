import AppKit
import AproidKit

/// Receives what the phone shares: files go to Downloads, links open in the browser,
/// and text lands on the clipboard.
final class SharePlugin: Plugin {
    let incoming: Set<String> = [PacketType.shareRequest]

    /// Called with each new or updated Recent entry, on any thread.
    var onActivity: ((Activity) -> Void)?

    /// Called when a file has arrived, to tell the user.
    var onFileReceived: ((URL, Device) -> Void)?

    private let folder: URL
    private let files = FileManager.default
    private let lock = NSLock()

    init(folder: URL) {
        self.folder = folder
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let share = Share(packet: packet) else { return }

        switch share {
        case .file(let name, let size): receive(packet, name: name, size: size, from: device)
        case .link(let link): open(link, from: device)
        case .text(let text): paste(text, from: device)
        }
    }

    private func receive(_ packet: NetworkPacket, name: String, size: Int64, from device: Device) {
        guard let reserved = reserveFile(Share.safeName(name)) else {
            onActivity?(Activity(.failed, title: name, detail: "Could not save to Downloads"))
            return
        }

        let (url, sink) = reserved

        let started = Activity(.receiving, title: url.lastPathComponent, detail: "Receiving \(Bytes.text(size)) from \(device.name)")
        onActivity?(started)

        let finish: (Error?) -> Void = { [weak self] error in
            try? sink.close()
            var done = started
            done.date = Date()

            if error == nil {
                done.kind = .received(url)
                done.detail = "Received · \(Bytes.text(size))"
                self?.onFileReceived?(url, device)
            } else {
                try? FileManager.default.removeItem(at: url)
                done.kind = .failed
                done.detail = "Transfer from \(device.name) stopped"
            }

            self?.onActivity?(done)
        }

        do {
            try device.receivePayload(packet, into: sink).whenComplete { result in
                if case .failure(let error) = result { finish(error) } else { finish(nil) }
            }
        } catch {
            finish(error)
        }
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
