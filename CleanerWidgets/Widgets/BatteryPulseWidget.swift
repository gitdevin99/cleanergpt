import SwiftUI
import WidgetKit

struct BatteryPulseWidget: Widget {
    let kind = "BatteryPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            BatteryPulseView(entry: entry)
        }
        .configurationDisplayName("Battery Pulse")
        .description("Battery percentage with a live charging pulse.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

private struct BatteryPulseView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ThemedWidgetBackground(theme: entry.theme, family: family) {
            switch family {
            case .systemSmall:     smallView
            case .systemMedium:    mediumView
            case .accessoryCircular: circularLock
            case .accessoryInline:   inlineLock
            default:               smallView
            }
        }
    }

    // MARK: - Sizes

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                percentStack
                Spacer()
                ringWithBolt
            }
        }
        .padding(14)
    }

    private var mediumView: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                Text(WidgetFormatters.percent(percentFraction))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(entry.theme.primaryText)
                Text(subtitleText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.theme.secondaryText)
            }
            Spacer()
            ringWithBolt
                .frame(width: 110, height: 110)
        }
        .padding(16)
    }

    private var circularLock: some View {
        ZStack {
            AccessoryWidgetBackground()
            OrbitRing(
                fraction: percentFraction,
                lineWidth: 5,
                trackColor: .white.opacity(0.25),
                ringFill: .white
            )
            .padding(4)
            VStack(spacing: 0) {
                Image(systemName: isCharging ? "bolt.fill" : "battery.100")
                    .font(.system(size: 12, weight: .bold))
                Text("\(Int(round(percentFraction * 100)))")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
        }
    }

    private var inlineLock: some View {
        let pct = WidgetFormatters.percent(percentFraction)
        return Label(isCharging ? "Charging \(pct)" : "Battery \(pct)",
                     systemImage: isCharging ? "bolt.fill" : "battery.100")
    }

    // MARK: - Shared pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: isCharging ? "bolt.fill" : "battery.100")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isCharging ? entry.theme.positive : entry.theme.accent)
            Text("Battery")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(entry.theme.secondaryText)
        }
    }

    private var percentStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WidgetFormatters.percent(percentFraction))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(entry.theme.primaryText)
            Text(subtitleText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(entry.theme.secondaryText)
                .lineLimit(1)
        }
    }

    private var ringWithBolt: some View {
        ZStack {
            OrbitRing(
                fraction: percentFraction,
                lineWidth: 8,
                trackColor: entry.theme.accentDim,
                ringFill: isCharging ? entry.theme.positive : entry.theme.accent
            )
            Image(systemName: isCharging ? "bolt.fill" : "battery.100")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(isCharging ? entry.theme.positive : entry.theme.accent)
                .shadow(color: (isCharging ? entry.theme.positive : entry.theme.accent).opacity(0.45),
                        radius: 6)
        }
        .frame(width: 72, height: 72)
    }

    // MARK: - Values

    private var percentFraction: Double {
        let lvl = entry.snapshot.battery.level
        return lvl < 0 ? 0 : lvl
    }

    private var isCharging: Bool {
        entry.snapshot.battery.state == "charging" || entry.snapshot.battery.state == "full"
    }

    private var subtitleText: String {
        if entry.snapshot.battery.isLowPower { return "Low Power Mode" }
        if entry.snapshot.battery.state == "charging" { return "Charging now" }
        if entry.snapshot.battery.state == "full"     { return "Fully charged" }
        return "On battery"
    }
}
