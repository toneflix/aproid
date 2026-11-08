import AppKit
import SwiftUI

/// The last few files, links and texts that went between the phone and this Mac.
struct RecentList: View {
    let items: [Activity]
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionTitle("Recent")
                Spacer()
                Button("Clear", action: clear)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 4)
            }

            // Refreshes the "2 min ago" times.
            TimelineView(.periodic(from: Date(), by: 30)) { context in
                VStack(spacing: 0) {
                    ForEach(items.prefix(5)) { item in
                        RecentRow(item: item, now: context.date)
                        if item.id != items.prefix(5).last?.id { Divider().padding(.leading, 56) }
                    }
                }
                .card(padding: 4)
            }
        }
    }
}

private struct RecentRow: View {
    let item: Activity
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(item.kind == .failed ? Theme.warn.opacity(0.15) : Theme.thumb)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: item.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(item.kind == .failed ? Theme.warn : Color.secondary)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.isInProgress ? item.detail : "\(item.detail) · \(RelativeTime.text(item.date, now: now))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    @ViewBuilder private var trailing: some View {
        switch item.kind {
        case .receiving, .sending:
            ProgressView().controlSize(.small)
        case .received(let url):
            LinkButton(title: "Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .link(let url):
            LinkButton(title: "Open") { NSWorkspace.shared.open(url) }
        case .sent, .failed, .text:
            EmptyView()
        }
    }
}

private struct LinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accent)
    }
}
