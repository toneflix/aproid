import AppKit
import Foundation
import UserNotifications

/// Notices the FlyyLink team sends with `flyylink-cli notify:send --channel=app`, shown in Notification
/// Center. Fetched when the licence is checked; the first fetch only records where to start. Mirrors ServerNotices.cs.
@MainActor
final class ServerNotices {
    nonisolated static let linkKey = "serverNoticeLink"

    private static let lastKey = "serverNotices.last"

    private let server: LicenceServer
    private let defaults = UserDefaults.standard

    init(server: LicenceServer) {
        self.server = server
    }

    func check(machine: String, secret: String?) async {
        let last = defaults.object(forKey: Self.lastKey) as? Int

        guard let reply = try? await server.notices(machine: machine, secret: secret, after: last) else { return }

        reply.notices.forEach(show)
        defaults.set(reply.latest, forKey: Self.lastKey)
    }

    static func open(_ link: String) {
        guard let url = URL(string: link), url.scheme == "https" else { return }

        NSWorkspace.shared.open(url)
    }

    private func show(_ notice: LicenceServer.Notice) {
        guard NotificationPlugin.isAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.message
        content.sound = .default
        if let link = notice.link { content.userInfo = [Self.linkKey: link] }

        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "server.notice.\(notice.id)", content: content, trigger: nil))
    }
}
