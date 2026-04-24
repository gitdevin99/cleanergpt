import SwiftUI

// MARK: - Preview snapshot
//
// Plain, in-app mirror of the values the real widgets consume. Everything the
// previews draw comes from this struct — no App Group I/O below this line —
// so the gallery renders identically even if the widget has never fired.

struct WidgetPreviewSnapshot {
    var batteryFraction: Double          // 0...1 (may be -1 if unknown)
    var isCharging: Bool
    var storageUsedFraction: Double      // 0...1
    var storageUsedBytes: Int64
    var storageTotalBytes: Int64
    var lastScanFreedBytes: Int64
    var lastScanAge: String

    static let placeholder = WidgetPreviewSnapshot(
        batteryFraction: 0.72,
        isCharging: false,
        storageUsedFraction: 0.63,
        storageUsedBytes: 95_000_000_000,
        storageTotalBytes: 128_000_000_000,
        lastScanFreedBytes: 1_800_000_000,
        lastScanAge: "2h ago"
    )
}

// MARK: - Formatters

enum WidgetPreviewFormatters {
    nonisolated(unsafe) static let byteCount: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB]
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func percent(_ fraction: Double) -> String {
        let clamped = max(0, min(1, fraction))
        return "\(Int((clamped * 100).rounded()))%"
    }

    static func relativeAge(of date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86_400 { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86_400))d ago"
    }
}

// MARK: - Face dispatch

struct WidgetPreviewFace: View {
    let kind: AppWidgetKind
    let theme: AppWidgetTheme
    let snapshot: WidgetPreviewSnapshot

    var body: some View {
        switch kind {
        case .batteryPulse: BatteryPulseFace(theme: theme, snapshot: snapshot)
        case .storageOrbit: StorageOrbitFace(theme: theme, snapshot: snapshot)
        case .combo:        ComboFace(theme: theme, snapshot: snapshot)
        case .deviceHealth: DeviceHealthFace(theme: theme, snapshot: snapshot)
        case .lastScan:     LastScanFace(theme: theme, snapshot: snapshot)
        case .quickClean:   QuickCleanFace(theme: theme, snapshot: snapshot)
        case .waterEject:   WaterEjectFace(theme: theme)
        case .dustClean:    DustCleanFace(theme: theme)
        }
    }
}

// MARK: - Battery Pulse

private struct BatteryPulseFace: View {
    let theme: AppWidgetTheme
    let snapshot: WidgetPreviewSnapshot

    var body: some View {
        let frac = max(0, min(1, snapshot.batteryFraction < 0 ? 0.72 : snapshot.batteryFraction))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: snapshot.isCharging ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Battery")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(theme.accentDim, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(WidgetPreviewFormatters.percent(frac))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            }
            .frame(width: 88, height: 88)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text(snapshot.isCharging ? "Charging" : "On battery")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
    }
}

// MARK: - Storage Orbit

private struct StorageOrbitFace: View {
    let theme: AppWidgetTheme
    let snapshot: WidgetPreviewSnapshot

    var body: some View {
        let frac = max(0, min(1, snapshot.storageUsedFraction))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Storage")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(theme.accentDim, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(
                        AngularGradient(
                            colors: [theme.accent, theme.positive, theme.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(WidgetPreviewFormatters.percent(frac))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text("used")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .frame(width: 90, height: 90)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text(usedOfTotal)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
    }

    private var usedOfTotal: String {
        let used = snapshot.storageUsedBytes > 0
            ? WidgetPreviewFormatters.byteCount.string(fromByteCount: snapshot.storageUsedBytes)
            : "80.6 GB"
        let total = snapshot.storageTotalBytes > 0
            ? WidgetPreviewFormatters.byteCount.string(fromByteCount: snapshot.storageTotalBytes)
            : "128 GB"
        return "\(used) / \(total)"
    }
}

// MARK: - Combo Dashboard

private struct ComboFace: View {
    let theme: AppWidgetTheme
    let snapshot: WidgetPreviewSnapshot

    var body: some View {
        let bat = max(0, min(1, snapshot.batteryFraction < 0 ? 0.72 : snapshot.batteryFraction))
        let stor = max(0, min(1, snapshot.storageUsedFraction))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Dashboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            HStack(spacing: 10) {
                miniRing(label: "Battery", frac: bat, color: theme.accent)
                miniRing(label: "Storage", frac: stor, color: theme.positive)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                Text("Clean now")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(theme.accent.opacity(0.18), in: Capsule(style: .continuous))
        }
        .padding(12)
    }

    private func miniRing(label: String, frac: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(theme.accentDim, lineWidth: 5)
                Circle().trim(from: 0, to: frac)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(WidgetPreviewFormatters.percent(frac))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            }
            .frame(width: 52, height: 52)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Device Health

private struct DeviceHealthFace: View {
    let theme: AppWidgetTheme
    let snapshot: WidgetPreviewSnapshot

    var body: some View {
        let bat = max(0, min(1, snapshot.batteryFraction < 0 ? 0.72 : snapshot.batteryFraction))
        let stor = max(0, min(1, snapshot.storageUsedFraction))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Device Health")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            HStack(spacing: 6) {
                healthCell(icon: "bolt.fill", value: WidgetPreviewFormatters.percent(bat), label: "Battery")
                healthCell(icon: "internaldrive.fill", value: WidgetPreviewFormatters.percent(stor), label: "Storage")
                healthCell(icon: "thermometer.medium", value: "OK", label: "Thermal")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func healthCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.accent)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(theme.accentDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Last Scan

private struct LastScanFace: View {
    let theme: AppWidgetTheme
    let snapshot: WidgetPreviewSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Last Scan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
            Text(snapshot.lastScanAge)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.primaryText)
            Text(freedCaption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.accent)
            Spacer(minLength: 6)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(theme.accent.opacity(0.55 + Double(i) * 0.09))
                        .frame(width: 10, height: CGFloat(10 + i * 6))
                }
                Spacer()
            }
        }
        .padding(12)
    }

    private var freedCaption: String {
        guard snapshot.lastScanFreedBytes > 0 else { return "No scans yet" }
        let freed = WidgetPreviewFormatters.byteCount.string(fromByteCount: snapshot.lastScanFreedBytes)
        return "freed \(freed)"
    }
}

// MARK: - Quick Clean

private struct QuickCleanFace: View {
    let theme: AppWidgetTheme
    let snapshot: WidgetPreviewSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Quick Clean")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
            Text(cta)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)
            Text(subcaption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            HStack {
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(14)
    }

    private var cta: String {
        if snapshot.lastScanFreedBytes > 0 {
            let freed = WidgetPreviewFormatters.byteCount.string(fromByteCount: snapshot.lastScanFreedBytes)
            return "Freed \(freed)"
        }
        return "Clean now"
    }

    private var subcaption: String {
        "Storage \(WidgetPreviewFormatters.percent(snapshot.storageUsedFraction)) used"
    }
}

// MARK: - Water Eject

private struct WaterEjectFace: View {
    let theme: AppWidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Water Eject")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(theme.accentDim, lineWidth: 1)
                    .frame(width: 84, height: 84)
                Circle()
                    .stroke(theme.accent.opacity(0.55), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: "drop.fill")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.accent, theme.accent.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: theme.accent.opacity(0.45), radius: 8)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text("Tap to eject • 30s")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
    }
}

// MARK: - Dust Clean

private struct DustCleanFace: View {
    let theme: AppWidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "wind")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Dust Clean")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(theme.accentDim, lineWidth: 1)
                    .frame(width: 84, height: 84)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.accent, theme.accent.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: theme.accent.opacity(0.45), radius: 8)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text("Tap to clean • 30s")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
    }
}
