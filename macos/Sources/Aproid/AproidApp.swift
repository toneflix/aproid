import AppKit
import SwiftUI

@main
struct AproidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            Image(nsImage: .aproidMenuBar)
        }
        .menuBarExtraStyle(.window)

        Window("Messages", id: AproidApp.messagesWindow) {
            MessagesWindow(store: model.messages, model: model)
        }
        .defaultSize(width: 900, height: 620)

        Window("Photos", id: AproidApp.photosWindow) {
            PhotosWindow(store: model.photos)
        }
        .defaultSize(width: 860, height: 640)

        Window("Call Audio", id: AproidApp.callAudioWindow) {
            CallAudioWindow(audio: model.callAudio)
        }
        .windowResizability(.contentSize)
    }

    static let messagesWindow = "messages"
    static let photosWindow = "photos"
    static let callAudioWindow = "callAudio"
}

/// Opens links handed to the app: aproid://share from the Share menu, and tel: numbers, such as one clicked in Safari.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            let model = AppModel.shared

            for url in urls {
                switch url.scheme?.lowercased() {
                case ShareRequest.scheme:
                    model.shareInbox.open(url)
                case "tel":
                    let number = (url.absoluteString.dropFirst("tel:".count).removingPercentEncoding ?? "")
                        .filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
                    model.dial(number, name: nil)
                default:
                    break
                }
            }
        }
    }
}
