import SwiftUI
import WidgetKit

struct QuickCleanWidget: Widget {
    let kind = "QuickCleanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            QuickCleanView(entry: entry)
        }
        .configurationDisplayName("Quick Clean")
        .description("One-tap shortcut to open Cleanup and free space.")
        .supportedFamilies([.systemSmall, .accessoryInline])
    }
}

private struct QuickCleanView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ThemedWidgetBackground(theme: entry.theme, family: family) {
            switch family {
            case .systemSmall:     smallView
            case .accessoryInline: inlineLock
            default:               smallView
            }
        }
        .widgetURL(URL(string: "cleanup://run/quick"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(entry.theme.accent)
                Text("Quick Clean")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.theme.secondaryText)
            }
            Spacer(minLength: 0)
            Text(ctaLine)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(entry.theme.primaryText)
                .lineLimit(2)
            Text(subcaption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(entry.theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            HStack {
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(entry.theme.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var inlineLock: some View {
        Label("Clean now", systemImage: "sparkles")
    }

    private var ctaLine: String {
        if let last = entry.snapshot.lastScan, last.freedBytes > 0 {
            let freed = WidgetFormatters.byteCount.string(fromByteCount: last.freedBytes)
            return "Freed \(freed)"
        }
        return "Clean now"
    }

    private var subcaption: String {
        let frac = entry.snapshot.storage.usedFraction
        return "Storage \(WidgetFormatters.percent(frac)) used"
    }
}
