import AppKit
import SwiftUI
import AproidKit

/// Where another computer sits next to this Mac, so the pointer and keyboard move across to it.
struct KeyboardMouseCard: View {
    let device: DeviceState
    @ObservedObject var model: AppModel

    private enum Placement: String, CaseIterable, Identifiable {
        case off, left, right, top, bottom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "Off"
            case .left: return "Left"
            case .right: return "Right"
            case .top: return "Above"
            case .bottom: return "Below"
            }
        }

        var edge: ScreenEdge? { ScreenEdge(rawValue: rawValue) }
    }

    var body: some View {
        let _ = model.inputEdgesVersion
        let edge = model.inputEdge(for: device.id)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? Theme.accent : Theme.tint)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(lucide: .mousePointer2, size: 14, weight: .semibold)
                            .foregroundStyle(isActive ? Color.white : Theme.accent)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Keyboard and mouse").font(.system(size: 13, weight: .semibold))
                    Text(status(edge))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Picker("\(device.name) is", selection: Binding(
                get: { edge.flatMap { Placement(rawValue: $0.rawValue) } ?? .off },
                set: { model.setInputEdge($0.edge, for: device.id) }
            )) {
                ForEach(Placement.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if edge != nil && model.inputNeedsAccess {
                Banner(
                    icon: .lock,
                    text: "Turn on Aproid under Accessibility.",
                    action: ("Open Settings", openAccessibility)
                )
            }
        }
        .card(padding: 12)
        .animation(.easeOut(duration: 0.2), value: isActive)
    }

    private var isActive: Bool {
        model.inputTarget == device.id || model.inputController == device.id
    }

    private func status(_ edge: ScreenEdge?) -> String {
        if model.inputTarget == device.id { return "Using \(device.name). Press Esc three times to return." }
        if model.inputController == device.id { return "\(device.name) is using this Mac." }
        guard let edge else { return "Which side is \(device.name) on?" }

        let side: String
        switch edge {
        case .left: side = "left"
        case .right: side = "right"
        case .top: side = "top"
        case .bottom: side = "bottom"
        }
        return "Move the pointer off the \(side) edge."
    }

    private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        model.retryInputAccess()
    }
}
