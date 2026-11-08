import Foundation
import UserNotifications
import AproidKit

/// Shows phone notifications in Notification Center. Replying or dismissing there
/// is sent back to the phone.
final class NotificationPlugin: NSObject, Plugin, UNUserNotificationCenterDelegate {
    let incoming: Set<String> = [PacketType.notification]

    private enum Category {
        static let plain = "phone.notification"
        static let replyable = "phone.notification.reply"
    }

    private enum Key {
        static let device = "device"
        static let id = "id"
        static let replyId = "replyId"
    }

    private let devices: DeviceRegistry
    private let center: UNUserNotificationCenter?

    /// True when running as a bundled app. `swift run` has no bundle, and
    /// Notification Center refuses to work without one.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    init(devices: DeviceRegistry) {
        self.devices = devices
        center = Self.isAvailable ? UNUserNotificationCenter.current() : nil
        super.init()

        guard let center else { return }

        let reply = UNTextInputNotificationAction(
            identifier: "reply",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message"
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.plain, actions: [], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: Category.replyable, actions: [reply], intentIdentifiers: [], options: [.customDismissAction]),
        ])
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Plugin

    func onPaired(_ device: Device) {
        device.send(NotificationRequests.requestAll())
    }

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let center else { return }

        if let id = PhoneNotification.cancelledId(packet) {
            center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(device: device.id, id: id)])
            return
        }

        guard let note = PhoneNotification(packet: packet) else { return }

        let content = UNMutableNotificationContent()
        content.title = note.title.isEmpty ? note.appName : note.title
        content.subtitle = note.title.isEmpty ? device.name : "\(note.appName) · \(device.name)"
        content.body = note.text
        content.categoryIdentifier = note.replyId == nil ? Category.plain : Category.replyable
        content.userInfo = [Key.device: device.id, Key.id: note.id, Key.replyId: note.replyId ?? ""]
        content.threadIdentifier = "\(device.id).\(note.appName)"
        if !note.silent { content.sound = .default }

        let request = UNNotificationRequest(identifier: Self.identifier(device: device.id, id: note.id), content: content, trigger: nil)
        center.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // A menu bar app is often frontmost; show banners anyway.
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let info = response.notification.request.content.userInfo
        guard let deviceId = info[Key.device] as? String,
              let id = info[Key.id] as? String,
              let device = devices[deviceId]
        else { return }

        if let text = response as? UNTextInputNotificationResponse,
           let replyId = info[Key.replyId] as? String, !replyId.isEmpty {
            device.send(NotificationRequests.reply(to: replyId, message: text.userText))
            return
        }

        if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            device.send(NotificationRequests.dismiss(id))
        }
    }

    private static func identifier(device: String, id: String) -> String {
        "\(device)/\(id)"
    }
}
