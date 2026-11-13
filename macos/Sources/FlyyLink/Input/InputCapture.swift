import AppKit
import FlyyLinkKit
import OSLog

/// Takes this Mac's keyboard and mouse over to another computer when the pointer leaves through the edge that
/// computer sits beyond, and hands them back when it returns. Runs on the main thread. Needs Accessibility access.
final class InputCapture {
    /// The edge of this Mac each paired computer sits beyond, by device id.
    var edges: () -> [String: ScreenEdge] = { [:] }

    /// True while another computer works this Mac, so its pointer doesn't cross on to a third one.
    var isControlled: () -> Bool = { false }

    /// Sends to a device; false when it isn't connected.
    var send: (String, RemoteInput) -> Bool = { _, _ in false }

    /// The computer the keyboard and mouse now work, or nil while they work this Mac.
    var onChange: ((String?) -> Void)?

    private(set) var remoteId: String?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var resumedAt = Date.distantPast
    private var escapes: [Date] = []
    private let log = Logger(subsystem: "com.toneflix.flyylink", category: "input")

    /// Asks macOS for Accessibility access when it is missing, which shows the prompt.
    static func hasAccess(prompting: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompting] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    /// Starts watching the pointer. Returns false without Accessibility access.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.hasAccess(prompting: false) else { return false }

        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .scrollWheel, .keyDown, .keyUp, .flagsChanged,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }

                let capture = Unmanaged<InputCapture>.fromOpaque(refcon).takeUnretainedValue()
                return capture.handle(type, event)
            },
            userInfo: refcon
        ) else {
            log.error("Could not watch the keyboard and mouse")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source

        return true
    }

    func stop() {
        returnHere(at: nil)

        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    /// The other computer sent the pointer back through `edge`, its own side facing this Mac.
    func resume(from deviceId: String, edge: ScreenEdge, position: Double) {
        guard remoteId == deviceId else { return }

        let bounds = DesktopBounds.current()
        returnHere(at: bounds.point(on: edge.opposite, at: position, inset: 6))
    }

    /// The other computer went away while it had the keyboard and mouse.
    func lost(_ deviceId: String) {
        guard remoteId == deviceId else { return }

        returnHere(at: nil)
    }

    // MARK: Events

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let remoteId else {
            if isMove(type) { crossIfAtEdge(event) }
            return Unmanaged.passUnretained(event)
        }

        if let input = translate(type, event), !send(remoteId, input) {
            returnHere(at: nil)
            return Unmanaged.passUnretained(event)
        }

        return nil
    }

    private func isMove(_ type: CGEventType) -> Bool {
        type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged
    }

    private func crossIfAtEdge(_ event: CGEvent) {
        guard Date().timeIntervalSince(resumedAt) > 0.4, !isControlled() else { return }

        let point = event.location
        let dx = event.getDoubleValueField(.mouseEventDeltaX)
        let dy = event.getDoubleValueField(.mouseEventDeltaY)
        let bounds = DesktopBounds.current()

        for (deviceId, edge) in edges() where bounds.reached(edge, by: point) && Self.heads(toward: edge, dx: dx, dy: dy) {
            let position = bounds.position(along: edge, of: point)
            guard send(deviceId, .enter(edge: edge.opposite, position: position, platform: RemoteInput.macOS)) else { continue }

            remoteId = deviceId
            CGAssociateMouseAndMouseCursorPosition(0)
            CGDisplayHideCursor(CGMainDisplayID())
            log.info("Keyboard and mouse moved to another computer")
            onChange?(deviceId)
            return
        }
    }

    private static func heads(toward edge: ScreenEdge, dx: Double, dy: Double) -> Bool {
        switch edge {
        case .left: return dx < 0
        case .right: return dx > 0
        case .top: return dy < 0
        case .bottom: return dy > 0
        }
    }

    private func translate(_ type: CGEventType, _ event: CGEvent) -> RemoteInput? {
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return .move(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
        case .leftMouseDown: return .button(.left, down: true)
        case .leftMouseUp: return .button(.left, down: false)
        case .rightMouseDown: return .button(.right, down: true)
        case .rightMouseUp: return .button(.right, down: false)
        case .otherMouseDown: return .button(.middle, down: true)
        case .otherMouseUp: return .button(.middle, down: false)
        case .scrollWheel:
            return .scroll(
                dx: -event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                dy: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            )
        case .keyDown, .keyUp:
            guard let name = MacKeys.name(event.getIntegerValueField(.keyboardEventKeycode)) else { return nil }

            if type == .keyDown, name == "Escape", escapedThreeTimes() {
                returnHere(at: nil)
                return nil
            }
            return .key(code: name, down: type == .keyDown)
        case .flagsChanged:
            guard let name = MacKeys.name(event.getIntegerValueField(.keyboardEventKeycode)), let flag = MacKeys.flag(for: name) else { return nil }

            return .key(code: name, down: event.flags.contains(flag))
        default:
            return nil
        }
    }

    /// Pressing Escape three times within a second brings the keyboard and mouse back, whatever the other side does.
    private func escapedThreeTimes() -> Bool {
        let now = Date()
        escapes = escapes.filter { now.timeIntervalSince($0) < 1 } + [now]

        return escapes.count >= 3
    }

    private func returnHere(at point: CGPoint?) {
        guard let remoteId else { return }

        _ = send(remoteId, .release)
        self.remoteId = nil
        escapes = []
        resumedAt = Date()

        if let point { CGWarpMouseCursorPosition(point) }
        CGAssociateMouseAndMouseCursorPosition(1)
        CGDisplayShowCursor(CGMainDisplayID())
        log.info("Keyboard and mouse are back on this Mac")
        onChange?(nil)
    }
}
