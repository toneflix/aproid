import SwiftUI

/// Opens another computer's screen here, and shows when that computer is watching this Mac.
struct ScreenShareCard: View {
    let device: DeviceState
    @ObservedObject var model: AppModel

    var body: some View {
        let watching = model.screenViewer == device.id

        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(watching ? Theme.accent : Theme.tint)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(lucide: .screenShare, size: 14, weight: .semibold)
                        .foregroundStyle(watching ? Color.white : Theme.accent)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Screen").font(.system(size: 13, weight: .semibold))
                Text(watching ? "\(device.name) is watching" : "View and control \(device.name)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if watching {
                Button("Stop") { model.stopScreenShare() }
                    .controlSize(.small)
            } else {
                Button("View") { model.mirror(device.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .card(padding: 12)
        .animation(.easeOut(duration: 0.2), value: watching)
    }
}
