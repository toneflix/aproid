import AppKit

/// Opens a file the phone sent, or shows it in Finder when it has moved or no app can open it.
enum ReceivedFile {
    @MainActor
    static func open(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Moved or deleted since: show the folder it was saved in.
            NSWorkspace.shared.open(url.deletingLastPathComponent())
            return
        }

        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error != nil else { return }
            Task { @MainActor in reveal(url) }
        }
    }

    @MainActor
    static func reveal(_ url: URL) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
