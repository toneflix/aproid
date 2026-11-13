import SwiftUI

/// A rounded surface: the system's Liquid Glass on macOS 26 and later, which follows the Mac's own
/// glass and transparency settings, or FlyyLink's solid card colour on older systems.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.radius
    var tint: Color?
    /// What older systems draw instead of glass.
    var fallback = AnyShapeStyle(Theme.card)

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(Glass.regular.tint(tint), in: shape)
        } else {
            solid(content, shape)
        }
        #else
        solid(content, shape)
        #endif
    }

    private func solid(_ content: Content, _ shape: RoundedRectangle) -> some View {
        content
            .background(tint.map(AnyShapeStyle.init) ?? fallback, in: shape)
            .overlay(shape.stroke(Theme.border))
    }
}

/// A window's backdrop: left to the system's glass on macOS 26 and later, FlyyLink's panel colour before.
struct GlassBackdrop: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content
        } else {
            content.background(Theme.panel)
        }
        #else
        content.background(Theme.panel)
        #endif
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = Theme.radius, tint: Color? = nil, fallback: AnyShapeStyle = AnyShapeStyle(Theme.card)) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, fallback: fallback))
    }

    func glassBackdrop() -> some View {
        modifier(GlassBackdrop())
    }
}
