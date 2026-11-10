import SwiftUI
import AproidKit

/// Other phones, tablets and computers on the network.
struct NearbyList: View {
    let devices: [DeviceState]
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Also nearby")

            ForEach(devices) { device in
                HStack(spacing: 12) {
                    DeviceArt(type: device.type, width: 20, screen: Theme.screen)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(status(device)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    action(device)
                }
                .card(padding: 10)
            }
        }
    }

    private func status(_ device: DeviceState) -> String {
        switch device.pairState {
        case .notPaired: return "Not paired"
        case .requested: return "Waiting for it to accept"
        case .requestedByPeer: return "Wants to pair next"
        case .paired: return device.battery.map { "Paired · \($0.charge)%" } ?? "Paired"
        }
    }

    @ViewBuilder private func action(_ device: DeviceState) -> some View {
        switch device.pairState {
        case .notPaired:
            SmallButton(title: "Pair") { model.requestPair(device.id) }
        case .requestedByPeer:
            SmallButton(title: "Not now") { model.reject(device.id) }
        case .paired:
            SmallButton(title: "Show") { model.selectedPhone = device.id }
        case .requested:
            ProgressView().controlSize(.small)
        }
    }
}

struct SmallButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentStrong)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Theme.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

/// Small uppercase heading above a list.
struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}
