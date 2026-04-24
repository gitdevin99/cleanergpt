import SwiftUI
import WidgetKit

struct ComboDashboardWidget: Widget {
    let kind = "ComboDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            ComboDashboardView(entry: entry)
        }
        .configurationDisplayName("Combo Dashboard")
        .description("Battery and storage together, plus a Clean-now shortcut on Large.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct ComboDashboardView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ThemedWidgetBackground(theme: entry.theme, family: family) {
            if family == .systemLarge {
                largeView
            } else {
                mediumView
            }
        }
        .widgetURL(URL(string: "cleanup://run/quick"))
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            tile(title: "Storage",
                 icon: "internaldrive.fill",
                 fraction: storage.usedFraction,
                 caption: WidgetFormatters.percent(storage.usedFraction),
                 subcaption: WidgetFormatters.byteCount.string(fromByteCount: storage.freeBytes) + " free",
                 accent: entry.theme.accent)

            tile(title: "Battery",
                 icon: isCharging ? "bolt.fill" : "battery.100",
                 fraction: batteryFraction,
                 caption: WidgetFormatters.percent(batteryFraction),
                 subcaption: batterySubtitle,
                 accent: isCharging ? entry.theme.positive : entry.theme.accent)
        }
        .padding(14)
    }

    private var largeView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                tile(title: "Storage",
                     icon: "internaldrive.fill",
                     fraction: storage.usedFraction,
                     caption: WidgetFormatters.percent(storage.usedFraction),
                     subcaption: WidgetFormatters.byteCount.string(fromByteCount: storage.freeBytes) + " free",
                     accent: entry.theme.accent)

                tile(title: "Battery",
                     icon: isCharging ? "bolt.fill" : "battery.100",
                     fraction: batteryFraction,
                     caption: WidgetFormatters.percent(batteryFraction),
                     subcaption: batterySubtitle,
                     accent: isCharging ? entry.theme.positive : entry.theme.accent)
            }

            // Whole widget is tappable via widgetURL; this is the visual
            // CTA only. Tapping anywhere on the widget opens Cleanup.
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                Text(cleanCTALabel)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [entry.theme.accent, entry.theme.accent.opacity(0.75)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .padding(14)
    }

    private func tile(
        title: String,
        icon: String,
        fraction: Double,
        caption: String,
        subcaption: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.theme.secondaryText)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
            }
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(entry.theme.primaryText)
                    Text(subcaption)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(entry.theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                OrbitRing(
                    fraction: fraction,
                    lineWidth: 6,
                    trackColor: entry.theme.accentDim,
                    ringFill: accent
                )
                .frame(width: 42, height: 42)
            }
        }
        .padding(12)
        .background(entry.theme.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Data

    private var storage: SharedDataStore.StorageInfo { entry.snapshot.storage }

    private var batteryFraction: Double {
        let lvl = entry.snapshot.battery.level
        return lvl < 0 ? 0 : lvl
    }

    private var isCharging: Bool {
        entry.snapshot.battery.state == "charging" || entry.snapshot.battery.state == "full"
    }

    private var batterySubtitle: String {
        if entry.snapshot.battery.isLowPower { return "Low Power" }
        if isCharging { return "Charging" }
        return "On battery"
    }

    private var cleanCTALabel: String {
        if let last = entry.snapshot.lastScan, last.freedBytes > 0 {
            let freed = WidgetFormatters.byteCount.string(fromByteCount: last.freedBytes)
            return "Clean now · freed \(freed) last time"
        }
        return "Clean now"
    }
}
