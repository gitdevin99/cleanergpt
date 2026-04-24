import SwiftUI
import WidgetKit

struct LastScanWidget: Widget {
    let kind = "LastScanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            LastScanView(entry: entry)
        }
        .configurationDisplayName("Last Scan")
        .description("When you last cleaned, how much you freed, and a trend of the last few scans.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct LastScanView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ThemedWidgetBackground(theme: entry.theme, family: family) {
            switch family {
            case .systemSmall:  smallView
            case .systemMedium: mediumView
            default:            smallView
            }
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            Text(headlineValue)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(entry.theme.primaryText)
            Text(headlineCaption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(entry.theme.secondaryText)
                .lineLimit(1)
        }
        .padding(14)
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                Text(headlineValue)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(entry.theme.primaryText)
                Text(headlineCaption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.theme.accent)
            }
            Spacer()
            TrendBars(history: history, accent: entry.theme.accent, track: entry.theme.accentDim)
                .frame(width: 120, height: 80)
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(entry.theme.accent)
            Text("Last Scan")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(entry.theme.secondaryText)
        }
    }

    // MARK: - Data

    private var scan: SharedDataStore.LastScanInfo? { entry.snapshot.lastScan }

    private var headlineValue: String {
        guard let scan else { return "—" }
        return WidgetFormatters.relativeAge(of: scan.date)
    }

    private var headlineCaption: String {
        guard let scan else { return "No scans yet" }
        let freed = WidgetFormatters.byteCount.string(fromByteCount: scan.freedBytes)
        return "freed \(freed)"
    }

    private var history: [SharedDataStore.LastScanInfo.HistoryEntry] {
        scan?.history ?? []
    }
}

private struct TrendBars: View {
    let history: [SharedDataStore.LastScanInfo.HistoryEntry]
    let accent: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            let maxBytes = max(1, history.map(\.freedBytes).max() ?? 1)
            let barCount = max(1, min(5, history.count))
            let spacing: CGFloat = 6
            let availableWidth = geo.size.width - spacing * CGFloat(barCount - 1)
            let barWidth = availableWidth / CGFloat(barCount)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let value = history.indices.contains(i) ? history[i].freedBytes : 0
                    let h = geo.size.height * CGFloat(Double(value) / Double(maxBytes))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(value > 0 ? accent : track)
                        .frame(width: barWidth, height: max(h, 4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
