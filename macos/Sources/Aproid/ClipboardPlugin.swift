import AppKit
import UniformTypeIdentifiers
import AproidKit

/// Shares the clipboard with paired phones both ways: text, pictures and copied files.
final class ClipboardPlugin: Plugin {
    let incoming: Set<String> = [PacketType.clipboard, PacketType.clipboardConnect, PacketType.clipboardFile]

    private let devices: DeviceRegistry
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let folder: URL

    /// Called on the main thread whenever something goes either way.
    var onSync: (() -> Void)?

    init(devices: DeviceRegistry) {
        self.devices = devices
        lastChangeCount = NSPasteboard.general.changeCount

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        folder = caches.appendingPathComponent("Aproid/Clipboard", isDirectory: true)
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
        if let file = Clipboard.file(packet) {
            receive(file, packet: packet, from: device)
            return
        }

        guard let text = Clipboard.content(packet) else { return }

        DispatchQueue.main.async { [self] in
            guard pasteboard.string(forType: .string) != text else { return }

            write { $0.setString(text, forType: .string) }
        }
    }

    /// Sends what is on the clipboard now, even if it was sent before. Call on the main thread.
    @discardableResult
    func send(to device: Device) -> Bool {
        let content = current()
        guard !content.isEmpty else { return false }

        return send(content, to: [device])
    }

    private func check() {
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount
        let paired = devices.all.filter(\.isPaired)
        guard !paired.isEmpty else { return }

        send(current(), to: paired)
    }

    // MARK: Reading the Mac clipboard

    private enum Content {
        case text(String)
        case files([URL])
        case image(Data)
        case empty

        var isEmpty: Bool { if case .empty = self { return true } else { return false } }
    }

    /// Copied files come first, since Finder also puts their names on the clipboard as text.
    private func current() -> Content {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter { !$0.hasDirectoryPath }
        if !files.isEmpty { return .files(files) }

        if let text = pasteboard.string(forType: .string), !text.isEmpty { return .text(text) }

        if let png = pasteboard.data(forType: .png) { return .image(png) }
        if let tiff = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return .image(png)
        }

        return .empty
    }

    @discardableResult
    private func send(_ content: Content, to targets: [Device]) -> Bool {
        switch content {
        case .text(let text):
            targets.forEach { $0.send(Clipboard.packet(text)) }
        case .files(let urls):
            DispatchQueue.global(qos: .userInitiated).async {
                urls.forEach { url in targets.forEach { Self.offer(url, to: $0) } }
            }
        case .image(let png):
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Copied image \(Self.stamp()).png")
            guard (try? png.write(to: url)) != nil else { return false }

            DispatchQueue.global(qos: .userInitiated).async {
                targets.forEach { Self.offer(url, to: $0) }
            }
        case .empty:
            return false
        }

        onSync?()
        return true
    }

    private static func offer(_ url: URL, to device: Device) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value,
              size <= Clipboard.fileLimit,
              let source = try? FileHandle(forReadingFrom: url)
        else { return }

        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        device.sendWithPayload(Clipboard.filePacket(name: url.lastPathComponent, mimeType: type), size: size, source: source) { _ in
            try? source.close()
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    // MARK: Writing to the Mac clipboard

    private func receive(_ file: ClipboardFile, packet: NetworkPacket, from device: Device) {
        // A fresh folder each time, so a pasted file keeps its own name.
        let target = folder.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent(file.safeName)
        let files = FileManager.default

        guard (try? files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil,
              files.createFile(atPath: target.path, contents: nil),
              let sink = try? FileHandle(forWritingTo: target),
              let download = try? device.receivePayload(packet, into: sink)
        else { return }

        download.whenComplete { [weak self] result in
            try? sink.close()
            guard case .success = result else {
                try? files.removeItem(at: target)
                return
            }

            DispatchQueue.main.async { self?.paste(target, mimeType: file.mimeType) }
        }
    }

    /// Pictures go on the clipboard as pictures, so they paste into any app; other files as files.
    private func paste(_ url: URL, mimeType: String) {
        if mimeType.hasPrefix("image/"), let image = NSImage(contentsOf: url) {
            write { $0.writeObjects([image, url as NSURL]) }
        } else {
            write { $0.writeObjects([url as NSURL]) }
        }
    }

    private func write(_ change: (NSPasteboard) -> Void) {
        pasteboard.clearContents()
        change(pasteboard)
        // Our own write must not be sent back to the phone.
        lastChangeCount = pasteboard.changeCount
        onSync?()
    }
}
