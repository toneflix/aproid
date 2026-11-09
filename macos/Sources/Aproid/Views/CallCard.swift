import SwiftUI

/// The call banner: who is calling, with Answer and Decline, or the running call with mute, audio route and Hang up.
struct CallCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var audio: HandsFreeAudio

    var body: some View {
        Group {
            if let call = model.call {
                content(call)
            } else {
                Color.clear
            }
        }
        .frame(width: 380, height: 112)
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
                RoundButton(icon: .phoneOff, color: .red, help: "Decline") { model.declineCall() }
                RoundButton(icon: .phone, color: .green, help: audio.isReady ? "Answer on this Mac" : "Answer on your phone") {
                    model.answerCall()
                }
            case .dialing, .talking:
                RoundButton(
                    icon: call.isMuted ? .micOff : .mic,
                    color: call.isMuted ? .primary : Theme.thumb,
                    foreground: call.isMuted ? Theme.card : .primary,
                    help: call.isMuted ? "Unmute" : "Mute"
                ) {
                    model.toggleMute()
                }
                if audio.isReady {
                    RoundButton(
                        icon: audio.audioOnMac ? .smartphone : .laptop,
                        color: Theme.thumb,
                        foreground: .primary,
                        help: audio.audioOnMac ? "Move the audio to your phone" : "Move the audio to this Mac"
                    ) {
                        model.switchCallAudio()
                    }
                }
                RoundButton(icon: .phoneOff, color: .red, help: "Hang up") { model.hangUp() }
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
            Text(call.name == nil ? "Incoming call · \(answersOn)" : "\(call.number) · \(answersOn)")
        case .dialing:
            Text("Calling from \(call.deviceName)…")
        case .talking(let since):
            TimelineView(.periodic(from: since, by: 1)) { context in
                HStack(spacing: 4) {
                    Text(Self.duration(context.date.timeIntervalSince(since)))
                    Text("·")
                    Image(lucide: audio.audioOnMac ? .laptop : .smartphone, size: 11)
                    Text(audio.audioOnMac ? "On this Mac" : "On your phone")
                }
            }
        }
    }

    private var answersOn: String {
        audio.isReady ? "Answers on this Mac" : (model.call?.deviceName ?? "Your phone")
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct RoundButton: View {
    let icon: Lucide
    let color: Color
    var foreground: Color = .white
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(lucide: icon, size: 16, weight: .semibold)
                .foregroundStyle(foreground)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color))
        }
        .buttonStyle(PressStyle())
        .help(help)
    }
}
