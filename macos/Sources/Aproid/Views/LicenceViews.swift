import SwiftUI

/// "12 days left in your trial", with Sign in and Buy.
struct TrialBanner: View {
    @ObservedObject var licence: LicenceModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.tint)
                .frame(width: 26, height: 26)
                .overlay(Image(lucide: .zap, size: 13).foregroundStyle(Theme.accent))
            Text(licence.trialText)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Sign in") { licence.openCard() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
            Button("Buy") { LicenceModel.buy() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .card(padding: 10)
    }
}

/// Signs in with an emailed code. While Aproid is locked it is the whole panel.
struct LicenceCard: View {
    @ObservedObject var licence: LicenceModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Theme.tint)
                    .frame(width: 56, height: 56)
                    .overlay(Image(lucide: .lock, size: 24).foregroundStyle(Theme.accent))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                if !licence.isLocked {
                    Button { licence.closeCard() } label: {
                        Image(lucide: .x, size: 13).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }

            VStack(spacing: 5) {
                Text(licence.title)
                    .font(.system(size: 17, weight: .bold))
                Text(licence.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            if licence.canRetry {
                Button("Try again") { licence.retry() }
                    .buttonStyle(PillStyle(prominent: true))
                    .disabled(licence.isBusy)
            }

            if licence.sentCode {
                Text("We sent a code to \(licence.email).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                TextField("Code", text: $licence.code)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit { licence.activate() }
                Button("Sign in") { licence.activate() }
                    .buttonStyle(PillStyle(prominent: true))
                    .disabled(licence.isBusy || licence.code.isEmpty)
                Button("Use another email") { licence.useAnotherEmail() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
            } else {
                TextField("Email", text: $licence.email)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { licence.sendCode() }
                Button("Send code") { licence.sendCode() }
                    .buttonStyle(PillStyle(prominent: true))
                    .disabled(licence.isBusy || licence.email.isEmpty)
            }

            if licence.isBusy {
                ProgressView().controlSize(.small)
            }
            if let error = licence.error {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.warn)
                    .multilineTextAlignment(.center)
            }

            Divider()
            HStack(spacing: 8) {
                Button("Buy Aproid") { LicenceModel.buy() }
                    .buttonStyle(PillStyle(prominent: false))
                Button("Your computers") { LicenceModel.manageComputers() }
                    .buttonStyle(PillStyle(prominent: false))
            }
        }
        .card(padding: 20)
        .onAppear { focused = true }
        .animation(.easeOut(duration: 0.2), value: licence.sentCode)
    }
}
