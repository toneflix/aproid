import SwiftUI
import AproidKit

/// The paired phone at the top of the panel, on the Toneflix gold: picture, name, connection and battery.
struct DeviceHero: View {
    let device: DeviceState
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            PhoneArt(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(device.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)

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
        .padding(16)
        .environment(\.colorScheme, .light)
        .background(Theme.gold, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var summary: String {
        let notifications = model.mirrorsNotifications ? "Notifications on" : "Notifications paused"
        return "\(notifications) · Clipboard synced"
    }
}
