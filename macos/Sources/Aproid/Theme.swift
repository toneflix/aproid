import AppKit
import SwiftUI

/// Aproid's colors and sizes, shared by every view. Each color has a light and a dark value.
enum Theme {
    static let accent = dynamic(light: 0x3346E0, dark: 0x8D9BFF)
    static let accentStrong = dynamic(light: 0x2233B8, dark: 0xB4BDFF)
    static let tint = dynamic(light: 0xECEEFF, dark: 0x8D9BFF, darkAlpha: 0.16)
    static let ok = dynamic(light: 0x127A4E, dark: 0x4FD39A)
    static let okTint = dynamic(light: 0xE3F5EC, dark: 0x4FD39A, darkAlpha: 0.14)
    static let warn = dynamic(light: 0x9A5B00, dark: 0xFFC46B)
    static let panel = dynamic(light: 0xF5F5F7, dark: 0x1E1E21)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2A2A2E)
    static let thumb = dynamic(light: 0xEFEFF3, dark: 0x34343A)
    static let track = dynamic(light: 0xE6E6EB, dark: 0xFFFFFF, darkAlpha: 0.10)
    static let device = dynamic(light: 0x1C1C20, dark: 0x3A3A40)
    static let screen = dynamic(light: 0xECEEFF, dark: 0x8D9BFF, darkAlpha: 0.22)
    static let border = Color.primary.opacity(0.08)
    static let dash = Color.primary.opacity(0.18)
    static let sub = Color.secondary

    static let panelWidth: CGFloat = 360
    static let radius: CGFloat = 14

    private static func dynamic(light: UInt32, dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light, alpha: isDark ? darkAlpha : 1)
        })
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension View {
    /// The rounded card every section sits on.
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.border))
    }
}
