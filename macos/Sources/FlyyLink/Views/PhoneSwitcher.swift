import SwiftUI
import FlyyLinkKit

/// How the panel switches between several paired devices.
enum PhoneSwitcherStyle: String, CaseIterable, Identifiable {
    case carousel
    case dropdown = "row"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .carousel: return "Card carousel"
        case .dropdown: return "Dropdown"
        }
    }
}

/// The shown phone's card with the next one peeking at the edge. Clicking it moves forward, round and round.
struct PhoneCarousel: View {
    let current: DeviceState
    let next: DeviceState
    @ObservedObject var model: AppModel

    /// How far the panel's padding lets the next card run to the window edge.
    private static let bleed: CGFloat = 14
    private static let peek: CGFloat = 22
    private static let gap: CGFloat = 8
    private static let cardWidth = Theme.panelWidth - bleed * 2 - peek

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: Self.gap) {
                DeviceHero(device: current, model: model)
                    .frame(width: Self.cardWidth)

                Button { model.showNextPhone() } label: {
                    DeviceHero(device: next, model: model)
                        .frame(width: Self.cardWidth)
                        .opacity(0.8)
                        .overlay(alignment: .leading) {
                            Image(lucide: .chevronRight, size: 12, weight: .semibold)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help("Show \(next.name)")
                .accessibilityLabel("Show \(next.name)")
            }
            .id(current.id)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .frame(width: Theme.panelWidth - Self.bleed, alignment: .leading)
        .clipped()
        .padding(.trailing, -Self.bleed)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: current.id)
    }
}

/// The device's name, which opens a list of the other paired devices in Dropdown mode.
struct DeviceNameMenu: View {
    let device: DeviceState
    @ObservedObject var model: AppModel

    var body: some View {
        let others = model.devices.filter { $0.pairState == .paired && $0.id != device.id }

        if model.switcherStyle == .dropdown && !others.isEmpty {
            Menu {
                ForEach(others) { other in
                    Button(other.name) { model.selectedPhone = other.id }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(lucide: .chevronDown, size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                    name
                }
                .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Switch to another device")
        } else {
            name
        }
    }

    private var name: some View {
        Text(device.name)
            .font(.system(size: 16, weight: .bold))
            .lineLimit(1)
    }
}

/// Picks which phone a window shows, when several are paired.
struct PhonePicker: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let phones = model.devices.filter { $0.pairState == .paired }

        if phones.count > 1 {
            Menu {
                ForEach(phones) { phone in
                    Toggle(phone.name, isOn: Binding(
                        get: { phone.id == model.primaryId },
                        set: { if $0 { model.selectedPhone = phone.id } }
                    ))
                }
            } label: {
                Label(current(phones)?.name ?? "Phone", lucide: .smartphone)
            }
            .help("Choose the phone to show")
        }
    }

    private func current(_ phones: [DeviceState]) -> DeviceState? {
        phones.first { $0.id == model.primaryId }
    }
}
