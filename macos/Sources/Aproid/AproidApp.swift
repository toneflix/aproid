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

            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            if !model.notificationsAvailable {
                Text("Notifications need the app bundle. Build it with macos/scripts/bundle.sh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            if model.devices.isEmpty {
                Text("Looking for your phone. Open Aproid on it, on the same Wi-Fi.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.devices) { device in
                    DeviceRow(device: device, model: model)
                }
            }

            Divider()
            Button("Quit Aproid") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct DeviceRow: View {
    let device: DeviceState
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: device.type == .tablet ? "ipad" : "iphone")
                VStack(alignment: .leading) {
                    Text(device.name)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                actions
            }

            if let code = device.code {
                Text(code)
                    .font(.system(.title3, design: .monospaced))
                    .help("Check the same code shows on the phone")
            }
        }
    }

    private var status: String {
        switch device.pairState {
        case .notPaired: return "Not paired"
        case .requested: return "Waiting for the phone to accept"
        case .requestedByPeer: return "Wants to pair. Check the code matches."
        case .paired:
            guard let battery = device.battery else { return "Paired" }
            return "Paired · \(battery.charge)%\(battery.isCharging ? " charging" : "")"
        }
    }

    @ViewBuilder private var actions: some View {
        switch device.pairState {
        case .notPaired:
            Button("Pair") { model.requestPair(device.id) }
        case .requestedByPeer:
            HStack {
                Button("Reject") { model.reject(device.id) }
                Button("Pair") { model.accept(device.id) }.keyboardShortcut(.defaultAction)
            }
        case .paired:
            Button("Unpair") { model.unpair(device.id) }
        case .requested:
            EmptyView()
        }
    }
}
