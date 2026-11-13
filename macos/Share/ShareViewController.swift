import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The "FlyyLink" entry in the Share menu. Collects what was shared and hands it to the app to send.
@objc(ShareViewController)
final class ShareViewController: NSViewController {
    private let collector = ShareCollector()

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = SendingView(frame: NSRect(x: 0, y: 0, width: 260, height: 120))
        preferredContentSize = view.frame.size
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        collector.collect(providers) { [weak self] request in
            self?.hand(request)
        }
    }

    private func hand(_ request: ShareRequest) {
        guard !request.isEmpty, let link = try? request.save(), NSWorkspace.shared.open(link) else {
            let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
            extensionContext?.cancelRequest(withError: error)
            return
        }

        // Leave the confirmation up for a moment so the share doesn't look like it did nothing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

/// Turns shared items into files and text the app can send.
final class ShareCollector {
    private let lock = NSLock()
    private var request = ShareRequest()

    func collect(_ providers: [NSItemProvider], done: @escaping (ShareRequest) -> Void) {
        sweepOldAttachments()

        let group = DispatchGroup()
        providers.forEach { provider in
            group.enter()
            load(provider) { group.leave() }
        }

        group.notify(queue: .main) { [self] in
            done(locked { request })
        }
    }

    private func load(_ provider: NSItemProvider, done: @escaping () -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [self] item, _ in
                if let url = Self.url(from: item) { add(file: url) }
                done()
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [self] item, _ in
                if let url = Self.url(from: item) { add(text: url.absoluteString) }
                done()
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [self] item, _ in
                if let text = item as? String { add(text: text) }
                done()
            }
        } else if let type = provider.registeredTypeIdentifiers.first {
            // A file that only exists for the moment, such as an image from a web page, is kept as a copy.
            provider.loadFileRepresentation(forTypeIdentifier: type) { [self] url, _ in
                if let url, let copy = try? Self.keep(url) { add(file: copy) }
                done()
            }
        } else {
            done()
        }
    }

    private func add(file: URL) {
        locked { request.files.append(file) }
    }

    private func add(text: String) {
        locked { request.texts.append(text) }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }

        return body()
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let text = item as? String { return URL(string: text) }

        return nil
    }

    private static func keep(_ url: URL) throws -> URL {
        let folder = ShareRequest.attachments.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let copy = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: copy)

        return copy
    }

    /// Copies are only needed until the app has sent them, so anything from an earlier day goes.
    private func sweepOldAttachments() {
        let manager = FileManager.default
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let folders = (try? manager.contentsOfDirectory(at: ShareRequest.attachments, includingPropertiesForKeys: [.creationDateKey])) ?? []

        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff { try? manager.removeItem(at: folder) }
        }
    }
}

/// The small sheet shown while the share is handed over.
final class SendingView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)

        let icon = NSHostingView(rootView: AproidMark().fill(AproidMark.gradient).frame(width: 34, height: 34))

        let title = NSTextField(labelWithString: "Sending to your phone")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let stack = NSStackView(views: [icon, title])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
