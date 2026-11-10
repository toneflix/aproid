import CoreGraphics
import AproidKit

/// The area every screen of this Mac covers together, in the top-left based coordinates mouse events use.
struct DesktopBounds {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    static func current() -> DesktopBounds {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)

        let union = displays.map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
        let rect = union.isNull ? CGDisplayBounds(CGMainDisplayID()) : union

        return DesktopBounds(minX: Double(rect.minX), minY: Double(rect.minY), maxX: Double(rect.maxX) - 1, maxY: Double(rect.maxY) - 1)
    }

    /// The main screen alone, where a fraction from the screen viewer lands.
    static func main() -> DesktopBounds {
        let rect = CGDisplayBounds(CGMainDisplayID())

        return DesktopBounds(minX: Double(rect.minX), minY: Double(rect.minY), maxX: Double(rect.maxX) - 1, maxY: Double(rect.maxY) - 1)
    }

    func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(Double(point.x), minX), maxX), y: min(max(Double(point.y), minY), maxY))
    }

    func position(along edge: ScreenEdge, of point: CGPoint) -> Double {
        edge.position(x: Double(point.x), y: Double(point.y), inMinX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    func point(on edge: ScreenEdge, at position: Double, inset: Double = 2) -> CGPoint {
        let point = edge.point(at: position, minX: minX, minY: minY, maxX: maxX, maxY: maxY, inset: inset)
        return CGPoint(x: point.x, y: point.y)
    }

    func reached(_ edge: ScreenEdge, by point: CGPoint) -> Bool {
        edge.reached(x: Double(point.x), y: Double(point.y), minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
