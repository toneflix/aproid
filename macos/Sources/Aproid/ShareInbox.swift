import AppKit

/// Sends what the Share extension hands over to the phone, waiting a little if the app has only just started.
@MainActor
final class ShareInbox {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func open(_ link: URL) {
        guard let request = ShareRequest.take(link), !request.isEmpty else { return }

        Task { await send(request) }
    }

    private func send(_ request: ShareRequest) async {
        guard let phone = await phone() else {
            NSSound.beep()
            return
        }

        if !request.files.isEmpty {
            model.sendFiles(request.files, to: phone)
        }
        request.texts.forEach { model.sendText($0, to: phone) }
    }

    /// The phone to send to, giving it a few seconds to connect when the share launched the app.
    private func phone() async -> String? {
        for _ in 0..<20 {
            if let id = model.primaryId { return id }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return nil
    }
}
