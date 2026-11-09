import AppKit
import SwiftUI

/// The 2×2 grid of things to do with the phone.
struct QuickActions: View {
    let device: DeviceState
    @ObservedObject var model: AppModel
    @ObservedObject var messages: MessagesStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ActionTile(icon: .volume2, title: "Ring phone", subtitle: "Full volume") {
                model.ring(device.id)
            }
            ActionTile(icon: .fileUp, title: "Send file", subtitle: "To Downloads") {
                model.chooseFiles(for: device.id)
            }
            ActionTile(icon: .clipboard, title: "Clipboard", subtitle: clipboardSubtitle) {
                model.sendClipboard(to: device.id)
            }
            ActionTile(
                icon: model.mirrorsNotifications ? .bellRing : .bellOff,
                title: "Notifications",
                subtitle: notificationsSubtitle,
                isOn: model.mirrorsNotifications
            ) {
                model.mirrorsNotifications.toggle()
            }
            ActionTile(icon: .messageSquare, title: "Messages", subtitle: messagesSubtitle) {
                showMessages()
            }
            ActionTile(icon: .phone, title: "Call", subtitle: "From your phone") {
                showMessages()
                messages.showsDialer = true
            }
            ActionTile(icon: .cast, title: "Mirror", subtitle: "See & use your phone") {
                model.mirror(device.id)
            }
            ActionTile(icon: .images, title: "Photos", subtitle: "Browse & download") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: AproidApp.photosWindow)
            }
        }
    }

    private var messagesSubtitle: String {
        messages.unreadCount == 0 ? "Your texts" : "\(messages.unreadCount) unread"
    }

    private func showMessages() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: AproidApp.messagesWindow)
    }

    private var clipboardSubtitle: String {
        guard let date = model.clipboardSyncedAt else { return "Send it now" }
        return "Synced \(RelativeTime.text(date))"
    }

    private var notificationsSubtitle: String {
        guard model.mirrorsNotifications else { return "Paused" }
        return model.notificationsToday == 0 ? "On" : "\(model.notificationsToday) today"
    }
}

/// One square action: an icon chip with a title and a hint.
struct ActionTile: View {
    let icon: Lucide
    let title: String
    let subtitle: String
    var isOn = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isOn ? Theme.tint : Theme.thumb)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(lucide: icon, size: 14, weight: .semibold)
                            .foregroundStyle(isOn ? Theme.accent : Color.secondary)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .card(padding: 10)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.accent.opacity(hovering ? 0.45 : 0))
            )
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
    }
}

/// Shrinks a little while pressed.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// "2 min ago" style times.
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func text(_ date: Date, now: Date = Date()) -> String {
        guard now.timeIntervalSince(date) >= 45 else { return "just now" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
