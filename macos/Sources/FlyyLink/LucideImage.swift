import AppKit
import SwiftUI

extension NSImage {
    /// A Lucide icon as a template image, so it takes the color of whatever it sits in.
    static func lucide(_ icon: Lucide, size: CGFloat, weight: Font.Weight = .regular) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let scale = rect.width / 24
            context.scaleBy(x: scale, y: scale)
            context.addPath(icon.path.cgPath)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(strokeWidth(weight))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.drawPath(using: icon.isSolid ? .fillStroke : .stroke)

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = icon.rawValue

        return image
    }

    /// Lucide draws at 2 points on 24; heavier weights thicken the line like SF Symbols do.
    private static func strokeWidth(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight, .thin, .light: return 1.5
        case .medium: return 2.15
        case .semibold: return 2.3
        case .bold, .heavy, .black: return 2.6
        default: return 2
        }
    }
}

extension Image {
    init(lucide icon: Lucide, size: CGFloat = 14, weight: Font.Weight = .regular) {
        self = Image(nsImage: .lucide(icon, size: size, weight: weight)).renderingMode(.template)
    }
}

extension Label where Title == Text, Icon == Image {
    init<S: StringProtocol>(_ title: S, lucide icon: Lucide, size: CGFloat = 14) {
        self.init { Text(title) } icon: { Image(lucide: icon, size: size) }
    }
}
