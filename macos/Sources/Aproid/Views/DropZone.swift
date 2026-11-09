import SwiftUI
import UniformTypeIdentifiers

/// Drop files here, or click, to send them to the phone.
struct DropZone: View {
    let deviceId: String
    @ObservedObject var model: AppModel

    @State private var targeted = false

    var body: some View {
        Button { model.chooseFiles(for: deviceId) } label: {
            HStack(spacing: 8) {
                Image(lucide: targeted ? .circleArrowDown : .arrowDownToLine, size: 14, weight: .semibold)
                Text(targeted ? "Release to send" : "Drop files here to send them to your phone")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(targeted ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(targeted ? Theme.tint : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(targeted ? Theme.accent : Theme.dash, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .scaleEffect(targeted ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Self.loadURLs(providers) { urls in
                Task { @MainActor in model.sendFiles(urls, to: deviceId) }
            }
            return true
        }
    }

    private static func loadURLs(_ providers: [NSItemProvider], then send: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { lock.withLock { urls.append(url) } }
                group.leave()
            }
        }

        group.notify(queue: .main) { send(urls) }
    }
}
