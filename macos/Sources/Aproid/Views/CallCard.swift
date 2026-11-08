import SwiftUI

/// The call banner: who is calling, with Answer and Decline, or the running call with Hang up.
struct CallCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let call = model.call {
                content(call)
            } else {
                Color.clear
            }
        }
        .frame(width: 360, height: 112)
    }

    private func content(_ call: ActiveCall) -> some View {
        HStack(spacing: 12) {
            Avatar(name: call.title, image: call.photo, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(call.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                status(call)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            switch call.phase {
            case .ringing:
                RoundButton(symbol: "phone.down.fill", color: .red, help: "Decline") { model.declineCall() }
                RoundButton(symbol: "phone.fill", color: .green, help: "Answer on your phone") { model.answerCall() }
            case .dialing, .talking:
                RoundButton(symbol: "phone.down.fill", color: .red, help: "Hang up") { model.hangUp() }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border))
        .padding(4)
    }

    @ViewBuilder private func status(_ call: ActiveCall) -> some View {
        switch call.phase {
        case .ringing:
            Text(call.name == nil ? "Incoming call · \(call.deviceName)" : "\(call.number) · \(call.deviceName)")
        case .dialing:
            Text("Calling from \(call.deviceName)…")
        case .talking(let since):
            // The audio stays on the phone: macOS doesn't let apps carry phone call audio.
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text("\(Self.duration(context.date.timeIntervalSince(since))) · Audio on your phone")
            }
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct RoundButton: View {
    let symbol: String
    let color: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color))
        }
        .buttonStyle(PressStyle())
        .help(help)
    }
}
