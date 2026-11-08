import AppKit
import SwiftUI
import AproidKit

@main
struct AproidApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Aproid", systemImage: "iphone.radiowaves.left.and.right") {
            MenuContent(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aproid").font(.headline)
            Text("This Mac: \(model.identity.deviceName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            if model.peers.isEmpty {
                Text("Looking for your phone. Open Aproid on it, on the same Wi-Fi.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.peers, id: \.identity.deviceId) { peer in
                    HStack {
                        Image(systemName: peer.identity.deviceType == .tablet ? "ipad" : "iphone")
                        VStack(alignment: .leading) {
                            Text(peer.identity.deviceName)
                            Text(peer.host).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
            Button("Quit Aproid") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
    }
}
