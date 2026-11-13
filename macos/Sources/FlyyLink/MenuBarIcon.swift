import AppKit
import SwiftUI

extension NSImage {
    /// The logo mark as a template image, so the menu bar tints it for light and dark.
    static let flyyLinkMenuBar: NSImage = {
        let height: CGFloat = 16
        let size = NSSize(width: (height * FlyyLinkMark.aspect).rounded(.up), height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let square = CGRect(x: rect.midX - height / 2, y: 0, width: height, height: height)
            context.addPath(FlyyLinkMark().path(in: square).cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = "FlyyLink"

        return image
    }()
}
