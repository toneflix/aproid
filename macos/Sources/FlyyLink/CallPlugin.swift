import AppKit
import SwiftUI
import FlyyLinkKit

/// A call on the phone that the Mac is showing.
struct ActiveCall: Equatable {
    enum Phase: Equatable {
        case ringing
        case dialing
        case talking(since: Date)
    }

    let deviceId: String
    let deviceName: String
    let number: String
    var name: String?
    var photo: NSImage?
    var phase: Phase
    var isMuted = false

    var title: String { name ?? number }
}

/// Follows the phone's calls ("kdeconnect.telephony").
final class CallPlugin: Plugin {
    let incoming: Set<String> = [PacketType.telephony]

    /// Called on any thread with each call update.
    var onState: ((Call.State, Device) -> Void)?

    func onPacket(_ packet: NetworkPacket, from device: Device) {
        guard let state = Call.state(packet) else { return }

        onState?(state, device)
    }
}

/// The floating card in the top right corner that shows a call, like a phone's incoming call banner.
@MainActor
final class CallPanel {
    private var panel: NSPanel?

    func show(_ model: AppModel) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let size = NSSize(width: 380, height: 112)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: CallCard(model: model, audio: model.callAudio))

        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 12))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        self.panel = panel
    }

    func hide() {
        guard let panel else { return }

        self.panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) {
            panel.orderOut(nil)
        }
    }
}
