import SwiftUI
import AproidKit

/// How the panel switches between several paired phones.
enum PhoneSwitcherStyle: String, CaseIterable, Identifiable {
    case carousel
    case row

    var id: String { rawValue }

    var title: String {
        switch self {
        case .carousel: return "Card carousel"
        case .row: return "Row of phones"
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

/// The paired phones, all connected at once. Picking one shows it in the panel, Messages and Photos.
struct PhoneSwitcher: View {
    let phones: [DeviceState]
    let focusedId: String?
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle("Your phones")
                Spacer()
                Text("\(phones.count) connected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ok)
                    .padding(.horizontal, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(phones) { phone in
                        PhoneChip(phone: phone, isFocused: phone.id == focusedId) {
                            model.selectedPhone = phone.id
                        }
                    }
                }
                .padding(1)
            }
        }
    }
}

/// One phone in the switcher: picture, name and battery, outlined in gold when it is the one shown.
private struct PhoneChip: View {
    let phone: DeviceState
    let isFocused: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    DeviceArt(type: phone.type, width: 14, screen: isFocused ? Theme.accent : Theme.screen)
                    Circle()
                        .fill(Theme.ok)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Theme.card, lineWidth: 1.5))
                        .offset(x: 3, y: 2)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(phone.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 110, alignment: .leading)
            .glassSurface(cornerRadius: 10, tint: isFocused || hovering ? Theme.tint : nil)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isFocused ? Theme.goldEdge : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .help(isFocused ? "\(phone.name) is shown" : "Show \(phone.name)")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private var detail: String {
        guard let battery = phone.battery else { return "Connected" }
        return battery.isCharging ? "\(battery.charge)% · Charging" : "\(battery.charge)%"
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
