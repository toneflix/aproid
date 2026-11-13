import AppKit
import Carbon.HIToolbox

/// System-wide ⌃⌥ shortcuts that work while another app is in front. Uses Carbon hot keys,
/// which need no Accessibility permission.
@MainActor
final class GlobalShortcuts {
    struct Shortcut {
        let keyCode: Int
        let symbol: String
        let title: String
        let action: () -> Void
    }

    static let modifiers = UInt32(controlKey | optionKey)
    private static let signature = OSType(0x4150_5244)

    let shortcuts: [Shortcut]

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }

            isEnabled ? register() : unregister()
        }
    }

    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(_ shortcuts: [Shortcut]) {
        self.shortcuts = shortcuts
    }

    fileprivate func fire(_ id: UInt32) {
        let index = Int(id) - 1
        guard shortcuts.indices.contains(index) else { return }

        shortcuts[index].action()
    }

    private func register() {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }

            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let shortcuts = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            let id = hotKey.id
            Task { @MainActor in shortcuts.fire(id) }

            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)

        for (index, shortcut) in shortcuts.enumerated() {
            var hotKey: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            RegisterEventHotKey(UInt32(shortcut.keyCode), Self.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
            if let hotKey { hotKeys.append(hotKey) }
        }
    }

    private func unregister() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []

        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

/// Opens or closes the menu bar panel, as clicking FlyyLink's icon does.
enum MenuBarPanel {
    @MainActor static func toggle() {
        let button = NSApp.windows
            .filter { String(describing: type(of: $0)).contains("StatusBarWindow") }
            .compactMap { $0.contentView.flatMap(statusButton(in:)) }
            .first

        button?.performClick(nil)
    }

    @MainActor private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }

        return view.subviews.lazy.compactMap(statusButton(in:)).first
    }
}
