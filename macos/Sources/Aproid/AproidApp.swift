import SwiftUI

@main
struct AproidApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Aproid", systemImage: "iphone.radiowaves.left.and.right") {
            MenuPanel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
