import AppKit
import SwiftUI

extension View {
    /// Keeps the hosting window exactly as tall as this view, growing or shrinking from the bottom edge.
    func fitsWindowHeight() -> some View {
        fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in WindowFitter(height: proxy.size.height) })
    }
}

/// An empty view that resizes its window to `height`. The menu bar window only grows on its own,
/// so without this it keeps a gap above and below the panel after content goes away.
private struct WindowFitter: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let height = height

        // The view joins its window after the first update, so look for it on the next pass.
        DispatchQueue.main.async { fit(view.window, to: height) }
    }

    private func fit(_ window: NSWindow?, to height: CGFloat) {
        guard let window, height > 0 else { return }

        let content = window.contentRect(forFrameRect: window.frame)
        guard abs(content.height - height) > 0.5 else { return }

        let target = NSRect(x: content.minX, y: content.maxY - height, width: content.width, height: height)
        window.setFrame(window.frameRect(forContentRect: target), display: true)
    }
}
