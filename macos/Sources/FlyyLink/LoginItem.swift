import OSLog
import ServiceManagement

/// Starts FlyyLink when the user logs in. Only works for the bundled app.
enum LoginItem {
    private static let log = Logger(subsystem: "com.toneflix.flyylink", category: "login")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Could not change the login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
