import AppKit
import Foundation
import OSLog
import UserNotifications
import AproidKit

/// Shows phone notifications in Notification Center. Replying, pressing a button or dismissing
/// there is sent back to the phone.
final class NotificationPlugin: NSObject, Plugin, UNUserNotificationCenterDelegate {
    let incoming: Set<String> = [PacketType.notification]

    private enum Category {
        static let plain = "phone.notification"
        static let replyable = "phone.notification.reply"
        static let missedCall = "phone.call.missed"
        static let file = "phone.file"
    }

    private enum Key {
        static let device = "device"
        static let id = "id"
        static let replyId = "replyId"
        static let file = "file"
        static let callBack = "callBack"
        static let actions = "actions"
        static let showInFinder = "showInFinder"
    }

    /// Notification Center shows at most this many buttons in a notification's Options menu.
    private static let maxActions = 4
    private static let actionPrefix = "action."

    private static let reply = UNTextInputNotificationAction(
        identifier: "reply",
        title: "Reply",
        options: [],
        textInputButtonTitle: "Send",
        textInputPlaceholder: "Message"
    )

    /// Every category registered so far. Each set of buttons needs its own, added the first time it is seen.
    private var categories: [String: UNNotificationCategory] = [:]

    private let log = Logger(subsystem: "com.toneflix.aproid.app", category: "notifications")
    private let devices: DeviceRegistry
    private let center: UNUserNotificationCenter?

    /// What each shown notification said, so a resend after reconnecting or an unchanged update doesn't pop up again.
    private var shown: [String: String] = [:]
    private let lock = NSLock()
    private let icons = NotificationIcons()
    private var enabled = true

    /// Paused from the menu: phone notifications are dropped instead of shown.
    var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }

    /// Called after a phone notification is shown, on any thread.
    var onShown: (() -> Void)?

    /// True when running as a bundled app. `swift run` has no bundle, and
    /// Notification Center refuses to work without one.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    init(devices: DeviceRegistry) {
        self.devices = devices
        center = Self.isAvailable ? UNUserNotificationCenter.current() : nil
        super.init()

        guard let center else { return }

        let base = [
            UNNotificationCategory(identifier: Category.plain, actions: [], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: Category.replyable, actions: [Self.reply], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(
                identifier: Category.missedCall,
                actions: [UNNotificationAction(identifier: Key.callBack, title: "Call back")],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: Category.file,
                actions: [UNNotificationAction(identifier: Key.showInFinder, title: "Show in Finder")],
                intentIdentifiers: [],
                options: []
            ),
        ]
        categories = Dictionary(uniqueKeysWithValues: base.map { ($0.identifier, $0) })
        center.setNotificationCategories(Set(base))
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
            let identifier = Self.identifier(device: device.id, id: id)
            lock.withLock { _ = shown.removeValue(forKey: identifier) }
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            return
        }

        guard isEnabled, let note = PhoneNotification(packet: packet) else { return }

        let identifier = Self.identifier(device: device.id, id: note.id)
        let summary = "\(note.title)\n\(note.text)"
        let isRepeat = lock.withLock { shown.updateValue(summary, forKey: identifier) == summary }
        guard !isRepeat else { return }

        let content = UNMutableNotificationContent()
        content.title = note.title.isEmpty ? note.appName : note.title
        content.subtitle = note.title.isEmpty ? device.name : "\(note.appName) · \(device.name)"
        content.body = note.text
        let actions = Array(note.actions.prefix(Self.maxActions))
        content.categoryIdentifier = category(replyable: note.replyId != nil, actions: actions, in: center)
        content.userInfo = [Key.device: device.id, Key.id: note.id, Key.replyId: note.replyId ?? "", Key.actions: actions]
        content.threadIdentifier = "\(device.id).\(note.appName)"
        if note.silent {
            // Already on the phone before we connected: list it without a banner.
            content.interruptionLevel = .passive
        } else {
            content.sound = .default
        }

        // The phone sends the app icon, or the sender's photo, as the payload.
        icons.icon(for: packet, hash: note.iconHash, from: device) { [weak self] icon in
            if let icon, let attachment = try? UNNotificationAttachment(identifier: "icon", url: icon) {
                content.attachments = [attachment]
            }

            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            if !note.silent { self?.onShown?() }
        }
    }

    /// The category for a notification with these buttons, registering it with Notification Center if it is new.
    private func category(replyable: Bool, actions: [String], in center: UNUserNotificationCenter) -> String {
        guard !actions.isEmpty else { return replyable ? Category.replyable : Category.plain }

        let identifier = ([replyable ? Category.replyable : Category.plain] + actions).joined(separator: "\u{1F}")
        let buttons = actions.enumerated().map { index, title in
            UNNotificationAction(identifier: Self.actionPrefix + String(index), title: title)
        }
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: (replyable ? [Self.reply] : []) + buttons,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let all: Set<UNNotificationCategory>? = lock.withLock {
            guard categories[identifier] == nil else { return nil }

            categories[identifier] = category
            return Set(categories.values)
        }
        if let all { center.setNotificationCategories(all) }

        return identifier
    }

    /// Tells the user a file arrived. Clicking it opens the file, and its button shows it in Finder.
    func announce(file url: URL, from device: Device) {
        guard let center else { return }

        let content = UNMutableNotificationContent()
        content.title = url.lastPathComponent
        content.subtitle = "From \(device.name)"
        content.body = "Saved to Downloads"
        content.categoryIdentifier = Category.file
        content.userInfo = [Key.file: url.path]
        content.sound = .default

        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// A missed call, with a Call back button that dials from the phone.
    func announceMissedCall(from caller: String, number: String, device: Device) {
        guard let center else { return }

        let content = UNMutableNotificationContent()
        content.title = "Missed call"
        content.subtitle = device.name
        content.body = caller
        content.categoryIdentifier = Category.missedCall
        content.userInfo = [Key.device: device.id, Key.callBack: number]
        content.sound = .default

        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // A menu bar app is often frontmost; show banners anyway, except for quiet ones.
        let isQuiet = notification.request.content.interruptionLevel == .passive
        completionHandler(isQuiet ? [.list] : [.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let info = response.notification.request.content.userInfo
        if let path = info[Key.file] as? String {
            guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }

            let url = URL(fileURLWithPath: path)
            let reveal = response.actionIdentifier == Key.showInFinder
            Task { @MainActor in reveal ? ReceivedFile.reveal(url) : ReceivedFile.open(url) }
            return
        }

        if let number = info[Key.callBack] as? String, response.actionIdentifier != UNNotificationDismissActionIdentifier {
            Task { @MainActor in AppModel.shared.dial(number, name: nil) }
            return
        }

        guard let deviceId = info[Key.device] as? String,
              let id = info[Key.id] as? String,
              let device = devices[deviceId]
        else {
            log.warning("Notification response for a device that is not connected")
            return
        }

        if let text = response as? UNTextInputNotificationResponse,
           let replyId = info[Key.replyId] as? String, !replyId.isEmpty {
            let sent = device.send(NotificationRequests.reply(to: replyId, message: text.userText))
            log.info("Reply to \(id, privacy: .public) sent: \(sent)")
            return
        }

        if response.actionIdentifier.hasPrefix(Self.actionPrefix),
           let index = Int(response.actionIdentifier.dropFirst(Self.actionPrefix.count)),
           let actions = info[Key.actions] as? [String], actions.indices.contains(index) {
            let sent = device.send(NotificationRequests.action(id: id, action: actions[index]))
            log.info("Pressed \(actions[index], privacy: .public) on \(id, privacy: .public): \(sent)")
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
