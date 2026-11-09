import AppKit
import SwiftUI
import AproidKit

/// The window that opens from the menu bar icon.
struct MenuPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(model: model)

            if let error = model.error {
                Banner(icon: .triangleAlert, text: error)
            }

            let phones = model.devices.filter { $0.pairState == .paired }
            if phones.count > 1 {
                PhoneSwitcher(phones: phones, focusedId: focused?.id, model: model)
                    .transition(.opacity)
            }

            main

            let others = model.devices.filter { $0.pairState != .paired && $0.id != focused?.id }
            if !others.isEmpty {
                NearbyList(devices: others, model: model)
            }

            if !model.recent.isEmpty {
                RecentList(items: model.recent) { model.clearRecent() }
            }

            if !model.notificationsAvailable {
                Banner(icon: .bellOff, text: "Notifications need the app bundle. Build it with macos/scripts/bundle.sh.")
            }

            PanelFooter(name: model.identity.deviceName)
        }
        .padding(14)
        .frame(width: Theme.panelWidth)
        .background(Theme.panel)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.devices)
        .animation(.easeOut(duration: 0.2), value: model.recent)
        .fitsWindowHeight()
    }

    /// The device the big cards are about: one asking to pair first, then the first paired one.
    private var focused: DeviceState? {
        model.devices.first { $0.pairState == .requestedByPeer || $0.pairState == .requested }
            ?? model.devices.first { $0.id == model.primaryId }
    }

    @ViewBuilder private var main: some View {
        if let device = focused, device.pairState != .paired {
            PairingCard(device: device, model: model)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else if let device = focused {
            DeviceHero(device: device, model: model)
            if model.finding == device.id, let location = device.location {
                FindCard(deviceName: device.name, location: location) { model.finding = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let media = device.media {
                NowPlayingCard(deviceId: device.id, media: media, model: model)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            QuickActions(device: device, model: model, messages: model.messages)
            CallAudioRow(audio: model.callAudio)
            DropZone(deviceId: device.id, model: model)
        } else {
            SearchingCard(hasNearby: !model.devices.isEmpty)
                .transition(.opacity)
            if model.phoneNearby || model.hotspotStatus != nil {
                HotspotCard(model: model)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

private struct PanelHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            AppGlyph()
            Text("Aproid")
                .font(.system(size: 15, weight: .bold))
            Spacer()
            Menu {
                Toggle("Show phone notifications", isOn: $model.mirrorsNotifications)
                Button("Open Downloads") { NSWorkspace.shared.open(AppModel.downloads) }

                let paired = model.devices.filter { $0.pairState == .paired }
                if !paired.isEmpty {
                    Divider()
                    ForEach(paired) { device in
                        Button("Unpair \(device.name)") { model.unpair(device.id) }
                    }
                }

                Divider()
                Button("Quit Aproid") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(lucide: .settings, size: 14, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
        .padding(.horizontal, 2)
    }
}

/// The app icon in miniature: the logo mark on its gold tile.
struct AppGlyph: View {
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(AproidMark.tile)
            .frame(width: size, height: size)
            .overlay(
                AproidMark()
                    .fill(AproidMark.gradient)
                    .frame(width: size * 0.66, height: size * 0.66)
            )
    }
}

/// Shown while no phone is paired.
private struct SearchingCard: View {
    let hasNearby: Bool
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ForEach(0..<2) { ring in
                    Circle()
                        .stroke(Theme.accent.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                        .scaleEffect(pulse ? 1.9 : 1)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(ring)), value: pulse)
                }
                Circle().fill(Theme.tint).frame(width: 64, height: 64)
                PhoneArt(width: 22)
            }
            .frame(height: 96)

            VStack(spacing: 5) {
                Text(hasNearby ? "Pick your phone to pair" : "Looking for your phone")
                    .font(.system(size: 16, weight: .bold))
                Text(hasNearby
                     ? "Choose it below, then check the same code shows on both screens."
                     : "Open Aproid on your Android phone, on the same Wi-Fi as this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .card(padding: 18)
        .onAppear { pulse = true }
    }
}

/// Shown when the phone is in Bluetooth range but not on this Mac's network.
private struct HotspotCard: View {
    @ObservedObject var model: AppModel

    private var explanation: String {
        model.phoneHotspotName == nil
            ? "It isn't on this Wi-Fi. Use its hotspot to get online and connect; this Mac leaves its current network."
            : "It isn't on this Wi-Fi. Your phone shows a switch to turn its hotspot on, and this Mac joins it."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.tint)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(lucide: .wifi, size: 14, weight: .semibold)
                        .foregroundStyle(Theme.accent)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("Your phone is nearby").font(.system(size: 13, weight: .semibold))
                Text(model.hotspotStatus ?? explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.hotspotStatus == nil {
                    Button(model.phoneHotspotName.map { "Use \($0)" } ?? "Use phone's hotspot") { model.joinPhoneHotspot() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Button("Cancel") { model.cancelHotspot() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .card(padding: 12)
    }
}

/// A one-line warning card.
struct Banner: View {
    let icon: Lucide
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(lucide: icon, size: 13).foregroundStyle(Theme.warn)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .card(padding: 10)
    }
}

private struct PanelFooter: View {
    let name: String

    var body: some View {
        HStack {
            Text("This Mac: \(name)")
                .lineLimit(1)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
