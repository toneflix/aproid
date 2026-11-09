import Foundation

/// What the Share extension hands to the app: files and text to send to the phone.
/// The extension saves it in a folder only it and the app write to, and opens `aproid://share/<id>`,
/// so a link alone can't make the app send files.
struct ShareRequest: Codable {
    var files: [URL] = []
    var texts: [String] = []

    var isEmpty: Bool { files.isEmpty && texts.isEmpty }

    static let scheme = "aproid"

    /// Saves the request from inside the extension and returns the link that hands it to the app.
    func save() throws -> URL {
        let id = UUID().uuidString
        try FileManager.default.createDirectory(at: Self.inbox, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.inbox.appendingPathComponent("\(id).json"), options: .atomic)

        return URL(string: "\(Self.scheme)://share/\(id)")!
    }

    /// Reads and removes the request a link from the extension points at.
    static func take(_ link: URL) -> ShareRequest? {
        guard link.scheme == scheme, link.host == "share", let id = UUID(uuidString: link.lastPathComponent) else { return nil }

        let file = inbox.appendingPathComponent("\(id.uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        guard let data = try? Data(contentsOf: file) else { return nil }

        return try? JSONDecoder().decode(ShareRequest.self, from: data)
    }

    /// Where items with no file of their own, such as an image dragged from a web page, are copied.
    static var attachments: URL { inbox.appendingPathComponent("Attachments") }

    /// The extension's sandbox allows this one folder; its own home is a container the app can't read without a prompt.
    private static var inbox: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()

        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Aproid/Shares")
    }
}
