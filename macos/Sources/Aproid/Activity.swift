import AproidKit
import Foundation
import UniformTypeIdentifiers

/// One line in the menu's Recent list.
struct Activity: Identifiable, Equatable {
    enum Kind: Equatable {
        case receiving
        case received(URL)
        case sending
        case sent
        case failed
        case link(URL)
        case text
    }

    let id = UUID()
    var kind: Kind
    let title: String
    var detail: String
    var date: Date

    /// How far a file has got while it moves.
    var progress: TransferProgress.Snapshot?

    init(_ kind: Kind, title: String, detail: String, date: Date = Date()) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.date = date
    }

    var isInProgress: Bool { kind == .receiving || kind == .sending }

    var icon: Lucide {
        switch kind {
        case .link: return .link
        case .text: return .clipboard
        case .failed: return .triangleAlert
        case .receiving, .received, .sending, .sent: return Self.fileIcon(title)
        }
    }

    private static func fileIcon(_ name: String) -> Lucide {
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return .file }

        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .film }
        if type.conforms(to: .audio) { return .audioLines }
        if type.conforms(to: .pdf) { return .fileText }
        if type.conforms(to: .archive) { return .fileArchive }

        return .file
    }
}

/// Byte counts the way Finder shows them.
enum Bytes {
    static func text(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// "120 MB of 1.2 GB · 41 MB/s · 28 s left"
    static func progress(_ reading: TransferProgress.Snapshot) -> String {
        var parts = ["\(text(reading.done)) of \(text(reading.total))"]

        if let speed = reading.bytesPerSecond { parts.append("\(text(speed))/s") }
        if let left = reading.secondsLeft { parts.append(timeLeft(left)) }

        return parts.joined(separator: " · ")
    }

    private static let minutes: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static func timeLeft(_ seconds: Int64) -> String {
        guard seconds >= 60, let text = minutes.string(from: TimeInterval(seconds)) else { return "\(max(seconds, 1)) s left" }

        return "\(text) left"
    }
}
