import SwiftUI
import WidgetKit

struct DeviceHealthWidget: Widget {
    let kind = "DeviceHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            DeviceHealthView(entry: entry)
        }
        .configurationDisplayName("Device Health")
        .description("Battery health, storage pressure, and thermal state at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

private struct DeviceHealthView: View {
    let entry: SnapshotEntry

    var body: some View {
        ThemedWidgetBackground(theme: entry.theme, family: .systemMedium) {
            HStack(spacing: 0) {
                column(
                    title: "Battery",
                    value: healthPct,
                    suffix: "%",
                    caption: batteryHealthStatus,
                    icon: "heart.fill",
                    tint: entry.theme.positive
                )
                divider
                column(
                    title: "Storage",
                    value: storagePct,
                    suffix: "%",
                    caption: storageStatus,
                    icon: "internaldrive.fill",
                    tint: entry.theme.accent
                )
                divider
                column(
                    title: "Thermal",
                    value: nil,
                    suffix: nil,
                    caption: thermalStatus,
                    icon: thermalIcon,
                    tint: thermalTint
                )
            }
            .padding(14)
        }
    }

    private func column(
        title: String,
        value: Int?,
        suffix: String?,
        caption: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.theme.secondaryText)
            }
            Group {
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(value)")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                        if let suffix {
                            Text(suffix)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(entry.theme.secondaryText)
                        }
                    }
                } else {
                    Text(caption.prefix(1).uppercased() + caption.dropFirst())
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(entry.theme.primaryText)

            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(entry.theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(entry.theme.accentDim)
            .frame(width: 1, height: 54)
    }

    // MARK: - Values

    private var healthPct: Int {
        entry.snapshot.thermal.batteryHealthPercent ?? Int(round(entry.snapshot.battery.level * 100))
    }

    private var batteryHealthStatus: String {
        if let h = entry.snapshot.thermal.batteryHealthPercent {
            return h >= 85 ? "Good" : (h >= 70 ? "Fair" : "Service soon")
        }
        return "Charge level"
    }

    private var storagePct: Int {
        Int(round(entry.snapshot.storage.usedFraction * 100))
    }

    private var storageStatus: String {
        let frac = entry.snapshot.storage.usedFraction
        if frac > 0.9  { return "Almost full" }
        if frac > 0.75 { return "Getting full" }
        return "Plenty free"
    }

    private var thermalIcon: String {
        switch entry.snapshot.thermal.state {
        case "fair":     return "thermometer.medium"
        case "serious":  return "thermometer.high"
        case "critical": return "exclamationmark.triangle.fill"
        default:         return "thermometer.low"
        }
    }

    private var thermalTint: Color {
        switch entry.snapshot.thermal.state {
        case "fair":     return .yellow
        case "serious":  return .orange
        case "critical": return .red
        default:         return entry.theme.positive
        }
    }

    private var thermalStatus: String {
        switch entry.snapshot.thermal.state {
        case "fair":     return "Warming up"
        case "serious":  return "Hot"
        case "critical": return "Critical"
        default:         return "Normal"
        }
    }
}
