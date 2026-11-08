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

    init(_ kind: Kind, title: String, detail: String, date: Date = Date()) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.date = date
    }

    var isInProgress: Bool { kind == .receiving || kind == .sending }

    var symbol: String {
        switch kind {
        case .link: return "link"
        case .text: return "doc.on.clipboard"
        case .failed: return "exclamationmark.triangle"
        case .receiving, .received, .sending, .sent: return Self.fileSymbol(title)
        }
    }

    private static func fileSymbol(_ name: String) -> String {
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return "doc" }

        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) { return "doc.zipper" }

        return "doc"
    }
}

/// Byte counts the way Finder shows them.
enum Bytes {
    static func text(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
