import AppKit
import AproidKit

/// Music and Spotify on this Mac, read and controlled with AppleScript so paired computers can show and control them.
/// Apps that aren't running are left alone, so asking never opens one. Call `players` and `perform` off the main thread.
final class LocalMedia {
    private struct App {
        let name: String
        let bundleId: String
        let changedNotification: String
        /// Spotify reports a track's length in milliseconds, Music in seconds.
        let durationInMs: Bool
        let stopCommand: String
    }

    private static let apps = [
        App(name: "Music", bundleId: "com.apple.Music", changedNotification: "com.apple.Music.playerInfo", durationInMs: false, stopCommand: "stop"),
        App(name: "Spotify", bundleId: "com.spotify.client", changedNotification: "com.spotify.client.PlaybackStateChanged", durationInMs: true, stopCommand: "pause"),
    ]

    /// Called on any thread when a player starts, stops or changes track.
    var onChange: (() -> Void)?

    private let lock = NSLock()

    func start() {
        for app in Self.apps {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(app.changedNotification), object: nil, queue: nil) { [weak self] _ in
                self?.onChange?()
            }
        }
    }

    func players() -> [MediaPlayer] {
        Self.apps.filter(isRunning).compactMap(read)
    }

    func perform(_ request: MediaRequest) {
        guard let name = request.player, let app = Self.apps.first(where: { $0.name == name }), isRunning(app) else { return }

        if let action = request.action {
            run(app, command(for: action, app: app))
        }
        if let position = request.seekTo {
            run(app, "set player position to \(Double(position) / 1000)")
        }
        if let volume = request.volume {
            run(app, "set sound volume to \(volume)")
        }
    }

    private func command(for action: MediaAction, app: App) -> String {
        switch action {
        case .playPause: return "playpause"
        case .play: return "play"
        case .pause: return "pause"
        case .next: return "next track"
        case .previous: return "previous track"
        case .stop: return app.stopCommand
        }
    }

    private func isRunning(_ app: App) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId).isEmpty
    }

    private func read(_ app: App) -> MediaPlayer? {
        let script = """
        set s to player state as text
        if s is "stopped" then return s
        set t to current track
        return s & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & (player position as text) & tab & ((duration of t) as text) & tab & (sound volume as text)
        """
        guard let output = run(app, script) else { return nil }

        let fields = output.components(separatedBy: "\t")
        guard fields.count >= 7 else { return nil }

        let seconds = { (text: String) in Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let duration = seconds(fields[5])

        var player = MediaPlayer(name: app.name)
        player.isPlaying = fields[0] == "playing"
        player.title = fields[1]
        player.artist = fields[2]
        player.album = fields[3]
        player.position = Int64(seconds(fields[4]) * 1000)
        player.length = Int64(app.durationInMs ? duration : duration * 1000)
        player.volume = Int(seconds(fields[6]))
        player.canGoNext = true
        player.canGoPrevious = true
        player.canSeek = player.length > 0

        return player
    }

    @discardableResult
    private func run(_ app: App, _ body: String) -> String? {
        let source = "tell application id \"\(app.bundleId)\"\n\(body)\nend tell"

        return lock.withLock {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)

            return error == nil ? result?.stringValue : nil
        }
    }
}
