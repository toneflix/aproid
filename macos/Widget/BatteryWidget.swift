import SwiftUI
import WidgetKit

/// Desktop and Notification Center widgets showing each paired phone's battery.
@main
struct AproidWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "battery", provider: BatteryTimeline()) { entry in
            BatteryWidgetView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "aproid://open"))
        }
        .configurationDisplayName("Phone battery")
        .description("Your phones' battery, from Aproid.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// The app reloads the widget whenever a battery changes, so one entry is enough.
struct BatteryTimeline: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        let saved = WidgetSnapshot.load()
        completion(BatteryEntry(date: Date(), snapshot: context.isPreview && saved.phones.isEmpty ? .preview : saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        completion(Timeline(entries: [BatteryEntry(date: Date(), snapshot: WidgetSnapshot.load())], policy: .never))
    }
}

struct BatteryWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let first = snapshot.phones.first {
                if family == .systemSmall {
                    SmallBattery(phone: first)
                } else {
                    MediumBattery(phones: Array(snapshot.phones.prefix(3)))
                }
            } else {
                NoPhone()
            }
        }
        .widgetBackground()
    }
}

/// One phone: a ring that fills with its charge.
private struct SmallBattery: View {
    let phone: WidgetSnapshot.Phone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                AproidMark()
                    .fill(BatteryStyle.gold)
                    .frame(width: 12, height: 12)
                Text(phone.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                BatteryRing(phone: phone, lineWidth: 9)
                    .frame(width: 76, height: 76)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            Text(BatteryStyle.status(phone))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .opacity(phone.isConnected ? 1 : 0.6)
    }
}

/// Up to three phones, each with a bar.
private struct MediumBattery: View {
    let phones: [WidgetSnapshot.Phone]

    var body: some View {
        HStack(spacing: 16) {
            if let first = phones.first {
                BatteryRing(phone: first, lineWidth: 10)
                    .frame(width: 92, height: 92)
                    .opacity(first.isConnected ? 1 : 0.6)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    AproidMark()
                        .fill(BatteryStyle.gold)
                        .frame(width: 12, height: 12)
                    Text("Aproid")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(phones) { phone in
                    BatteryRow(phone: phone)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct BatteryRow: View {
    let phone: WidgetSnapshot.Phone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: phone.isTablet ? "ipad" : "iphone")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(phone.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if phone.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(BatteryStyle.color(phone))
                }
                Text(phone.charge.map { "\($0)%" } ?? "–")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(phone.isLow ? BatteryStyle.color(phone) : .primary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(BatteryStyle.color(phone))
                        .frame(width: proxy.size.width * BatteryStyle.fraction(phone))
                }
            }
            .frame(height: 5)
        }
        .opacity(phone.isConnected ? 1 : 0.55)
    }
}

private struct BatteryRing: View {
    let phone: WidgetSnapshot.Phone
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: BatteryStyle.fraction(phone))
                .stroke(BatteryStyle.color(phone), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                if phone.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BatteryStyle.color(phone))
                }
                Text(phone.charge.map { "\($0)" } ?? "–")
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    + Text(phone.charge == nil ? "" : "%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
    }
}

private struct NoPhone: View {
    var body: some View {
        VStack(spacing: 8) {
            AproidMark()
                .fill(BatteryStyle.gold)
                .frame(width: 28, height: 28)
            Text("No phone yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Pair one in Aproid")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum BatteryStyle {
    static let gold = LinearGradient(
        colors: [Color(red: 0.965, green: 0.757, blue: 0.004), Color(red: 0.733, green: 0.549, blue: 0.004)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func color(_ phone: WidgetSnapshot.Phone) -> Color {
        if phone.isCharging { return Color(red: 0.31, green: 0.83, blue: 0.60) }
        if phone.isLow { return Color(red: 1.0, green: 0.36, blue: 0.33) }
        return Color(red: 0.965, green: 0.757, blue: 0.004)
    }

    static func fraction(_ phone: WidgetSnapshot.Phone) -> CGFloat {
        CGFloat(min(max(phone.charge ?? 0, 0), 100)) / 100
    }

    static func status(_ phone: WidgetSnapshot.Phone) -> String {
        if !phone.isConnected { return "Not connected" }
        if phone.isCharging { return "Charging" }
        if phone.isLow { return "Battery low" }
        return "Connected"
    }
}

private extension View {
    /// macOS 14 draws the widget's background and margins itself; older systems need them here.
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(macOS 14.0, *) {
            containerBackground(.background, for: .widget)
        } else {
            padding(14)
        }
    }
}
