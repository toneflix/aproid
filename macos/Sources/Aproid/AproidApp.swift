import AppKit
import SwiftUI

@main
struct AproidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Aproid", systemImage: "iphone.radiowaves.left.and.right") {
            MenuPanel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Messages", id: AproidApp.messagesWindow) {
            MessagesWindow(store: model.messages, model: model)
        }
        .defaultSize(width: 900, height: 620)
    }

    static let messagesWindow = "messages"
}

/// Opens tel: links, such as a phone number clicked in Safari, by calling from the phone.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "tel" {
            let number = (url.absoluteString.dropFirst("tel:".count).removingPercentEncoding ?? "")
                .filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
            Task { @MainActor in AppModel.shared.dial(number, name: nil) }
        }
    }
}
