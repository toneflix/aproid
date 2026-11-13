import Foundation

/// What the desktop widget shows: each paired phone's battery. The app saves it whenever a phone's
/// battery or connection changes, and the widget reads it. Built into both the app and the widget.
struct WidgetSnapshot: Codable, Equatable {
    struct Phone: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var isTablet = false
        /// 0 to 100, or nil before the phone has reported it.
        var charge: Int?
        var isCharging = false
        var isLow = false
        var isConnected = true
    }

    /// The phone the app is showing comes first.
    var phones: [Phone] = []

    static let empty = WidgetSnapshot()

    static let preview = WidgetSnapshot(phones: [
        Phone(id: "1", name: "Pixel 9", charge: 82, isCharging: true),
        Phone(id: "2", name: "Galaxy Tab", isTablet: true, charge: 41),
        Phone(id: "3", name: "TECNO", charge: 12, isLow: true, isConnected: false),
    ])

    static func load() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: file), let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }

    /// The widget's sandbox can read this one folder; its own home is a container the app can't see.
    private static var folder: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()

        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/FlyyLink/Widget")
    }

    private static var file: URL { folder.appendingPathComponent("snapshot.json") }
}
