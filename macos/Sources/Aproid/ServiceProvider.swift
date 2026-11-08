import AppKit

/// The "Send to Phone with Aproid" item in the Services menu and Finder's right-click menu.
final class ServiceProvider: NSObject {
    @objc func sendToPhone(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let link = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first { !$0.isFileURL }
        let text = pasteboard.string(forType: .string)

        Task { @MainActor in
            let model = AppModel.shared
            guard let phone = model.devices.first(where: { $0.pairState == .paired }) else {
                NSSound.beep()
                return
            }

            if !files.isEmpty {
                model.sendFiles(files, to: phone.id)
            } else if let link {
                model.sendText(link.absoluteString, to: phone.id)
            } else if let text, !text.isEmpty {
                model.sendText(text, to: phone.id)
            }
        }
    }
}
