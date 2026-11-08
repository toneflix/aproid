import SwiftUI
import AproidKit

/// The paired phone at the top of the panel: picture, name, connection and battery.
struct DeviceHero: View {
    let device: DeviceState
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            PhoneArt(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                name

                HStack(spacing: 6) {
                    Circle().fill(Theme.ok).frame(width: 7, height: 7)
                    Text("Connected over Wi-Fi")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ok)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.okTint, in: Capsule())

                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            BatteryRing(charge: device.battery?.charge, isCharging: device.battery?.isCharging ?? false)
        }
        .card(padding: 16)
    }

    /// With several phones paired, the name is a menu to switch between them.
    @ViewBuilder private var name: some View {
        let others = model.devices.filter { $0.pairState == .paired && $0.id != device.id }
        let title = Text(device.name).font(.system(size: 16, weight: .bold)).lineLimit(1)

        if others.isEmpty {
            title
        } else {
            Menu {
                ForEach(others) { other in
                    Button(other.name) { model.selectedPhone = other.id }
                }
            } label: {
                HStack(spacing: 4) {
                    title
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Switch to another phone")
        }
    }

    private var summary: String {
        let notifications = model.mirrorsNotifications ? "Notifications on" : "Notifications paused"
        return "\(notifications) · Clipboard synced"
    }
}
