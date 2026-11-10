import AppIntents
import Foundation
import AproidKit

// Actions for the Shortcuts app and Spotlight. Each one takes an optional phone; without one it uses
// the phone the panel is showing.

struct PhoneEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Phone"
    static let defaultQuery = PhoneQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    @MainActor
    static func paired() -> [PhoneEntity] {
        AppModel.shared.devices
            .filter { $0.pairState == .paired }
            .map { PhoneEntity(id: $0.id, name: $0.name) }
    }
}

struct PhoneQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PhoneEntity] {
        PhoneEntity.paired().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PhoneEntity] {
        PhoneEntity.paired()
    }
}

enum AproidIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noPhone
    case noBattery

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noPhone: return "No paired phone is connected to Aproid."
        case .noBattery: return "The phone hasn't reported its battery yet."
        }
    }
}

/// The phone an action is for: the one picked, or else the one the panel shows. It must be connected.
@MainActor
private func phoneId(_ phone: PhoneEntity?) throws -> String {
    let model = AppModel.shared
    guard let id = phone?.id ?? model.primaryId, model.devices.contains(where: { $0.id == id && $0.pairState == .paired }) else {
        throw AproidIntentError.noPhone
    }
    return id
}

struct RingPhoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Ring Phone"
    static let description = IntentDescription("Rings your phone, even when it's on silent, so you can find it.")

    @Parameter(title: "Phone")
    var phone: PhoneEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.ring(try phoneId(phone))
        return .result()
    }
}

struct SendClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Clipboard to Phone"
    static let description = IntentDescription("Sends what you last copied on this Mac to your phone's clipboard.")

    @Parameter(title: "Phone")
    var phone: PhoneEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.sendClipboard(to: try phoneId(phone))
        return .result()
    }
}

struct SendTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Text to Phone"
    static let description = IntentDescription("Sends text or a link to your phone. Links open there.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Phone")
    var phone: PhoneEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$text) to \(\.$phone)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.sendText(text, to: try phoneId(phone))
        return .result()
    }
}

struct SendFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Files to Phone"
    static let description = IntentDescription("Sends files to your phone's Downloads folder.")

    @Parameter(title: "Files", supportedTypeIdentifiers: ["public.item"])
    var files: [IntentFile]

    @Parameter(title: "Phone")
    var phone: PhoneEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$files) to \(\.$phone)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let id = try phoneId(phone)

        // Files that only exist in memory, such as a photo from an earlier action, are saved first.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Aproid Shortcuts", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let urls = try files.map { file -> URL in
            if let url = file.fileURL { return url }

            let url = folder.appendingPathComponent(file.filename.isEmpty ? UUID().uuidString : file.filename)
            try file.data.write(to: url, options: .atomic)
            return url
        }

        AppModel.shared.sendFiles(urls, to: id)
        return .result()
    }
}

struct MirrorPhoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mirror Phone Screen"
    static let description = IntentDescription("Shows your phone's screen on this Mac. The phone asks you to allow it.")

    @Parameter(title: "Phone")
    var phone: PhoneEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.mirror(try phoneId(phone))
        return .result()
    }
}

struct GetBatteryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Phone Battery"
    static let description = IntentDescription("Gives your phone's battery level, from 0 to 100.")

    @Parameter(title: "Phone")
    var phone: PhoneEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let id = try phoneId(phone)
        guard let charge = AppModel.shared.devices.first(where: { $0.id == id })?.battery?.charge else {
            throw AproidIntentError.noBattery
        }
        return .result(value: charge)
    }
}

/// Ready-made shortcuts, so the actions work from Spotlight and Siri without building a shortcut.
struct AproidShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RingPhoneIntent(), phrases: ["Ring my phone with \(.applicationName)", "Find my phone with \(.applicationName)"])
        AppShortcut(intent: SendClipboardIntent(), phrases: ["Send clipboard to phone with \(.applicationName)"])
        AppShortcut(intent: MirrorPhoneIntent(), phrases: ["Mirror my phone with \(.applicationName)"])
        AppShortcut(intent: GetBatteryIntent(), phrases: ["Check phone battery with \(.applicationName)"])
    }
}
