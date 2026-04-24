import SwiftUI
import WidgetKit

struct StorageOrbitWidget: Widget {
    let kind = "StorageOrbitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            StorageOrbitView(entry: entry)
        }
        .configurationDisplayName("Storage Orbit")
        .description("Storage use with a per-category breakdown ring.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

private struct StorageOrbitView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ThemedWidgetBackground(theme: entry.theme, family: family) {
            switch family {
            case .systemSmall:       smallView
            case .systemMedium:      mediumView
            case .accessoryCircular: circularLock
            case .accessoryInline:   inlineLock
            default:                 smallView
            }
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WidgetFormatters.percent(storage.usedFraction))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(entry.theme.primaryText)
                    Text("Used")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(entry.theme.secondaryText)
                }
                Spacer()
                ring
                    .frame(width: 68, height: 68)
            }
        }
        .padding(14)
    }

    private var mediumView: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                Text(WidgetFormatters.percent(storage.usedFraction))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(entry.theme.primaryText)
                Text(WidgetFormatters.byteCount.string(fromByteCount: storage.usedBytes)
                     + " of "
                     + WidgetFormatters.byteCount.string(fromByteCount: storage.totalBytes))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.theme.accent)
                Text(topCategoryLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(entry.theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            ring
                .frame(width: 108, height: 108)
        }
        .padding(16)
    }

    private var circularLock: some View {
        ZStack {
            AccessoryWidgetBackground()
            OrbitRing(
                fraction: storage.usedFraction,
                lineWidth: 5,
                trackColor: .white.opacity(0.25),
                ringFill: .white
            )
            .padding(4)
            VStack(spacing: 0) {
                Image(systemName: "internaldrive.fill").font(.system(size: 10, weight: .bold))
                Text("\(Int(round(storage.usedFraction * 100)))")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
        }
    }

    private var inlineLock: some View {
        Label("Storage \(WidgetFormatters.percent(storage.usedFraction))",
              systemImage: "internaldrive.fill")
    }

    // MARK: - Shared

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(entry.theme.accent)
            Text("Storage")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(entry.theme.secondaryText)
        }
    }

    private var ring: some View {
        ZStack {
            OrbitRing(
                fraction: storage.usedFraction,
                segments: categorySegments,
                lineWidth: 10,
                trackColor: entry.theme.accentDim,
                ringFill: entry.theme.accent
            )
            Image(systemName: "cylinder.split.1x2.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(entry.theme.accent)
                .shadow(color: entry.theme.accent.opacity(0.4), radius: 6)
        }
    }

    // MARK: - Data

    private var storage: SharedDataStore.StorageInfo { entry.snapshot.storage }

    /// Segmented arcs around the ring, one per storage category.
    private var categorySegments: [OrbitRing.Segment] {
        guard storage.totalBytes > 0 else { return [] }
        let total = Double(storage.totalBytes)
        let palette: [String: Color] = [
            "photos": entry.theme.accent,
            "videos": entry.theme.accent.opacity(0.68),
            "apps":   entry.theme.positive,
            "other":  entry.theme.secondaryText
        ]
        return storage.byCategory
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { (key, bytes) in
                OrbitRing.Segment(
                    id: key,
                    fraction: Double(bytes) / total,
                    color: palette[key] ?? entry.theme.accentDim
                )
            }
    }

    private var topCategoryLine: String {
        guard let top = storage.byCategory.max(by: { $0.value < $1.value }), top.value > 0 else {
            return "Free: " + WidgetFormatters.byteCount.string(fromByteCount: storage.freeBytes)
        }
        let label = top.key.capitalized
        let size = WidgetFormatters.byteCount.string(fromByteCount: top.value)
        return "\(label) \(size)"
    }
}
