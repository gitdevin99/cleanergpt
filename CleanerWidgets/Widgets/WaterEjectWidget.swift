import SwiftUI
import WidgetKit

/// Water-ejection widget.
///
/// Tapping the widget opens the host app via a `cleanup://` deep link;
/// the app then starts the 165 Hz tone through `SharedToneEngine` and
/// auto-suspends back to the Home Screen so audio keeps playing.
struct WaterEjectWidget: Widget {
    let kind = "WaterEjectWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            WaterEjectView(entry: entry)
        }
        .configurationDisplayName("Water Eject")
        .description("Tap to open Cleanup and eject water from your speaker.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

private struct WaterEjectView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ThemedWidgetBackground(theme: entry.theme, family: family) {
            switch family {
            case .systemSmall:       smallView
            case .systemMedium:      mediumView
            case .accessoryCircular: circularLock
            default:                 smallView
            }
        }
        .widgetURL(URL(string: "cleanup://run/water"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(entry.theme.accent)
                Text("Water Eject")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.theme.secondaryText)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(entry.theme.accentDim, lineWidth: 1)
                    .frame(width: 84, height: 84)
                Circle()
                    .stroke(entry.theme.accent.opacity(0.55), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: "drop.fill")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [entry.theme.accent, entry.theme.accent.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: entry.theme.accent.opacity(0.45), radius: 8)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text("Tap to eject")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(entry.theme.cardFill)
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(entry.theme.accent.opacity(0.45), lineWidth: 1)
                    .frame(width: 110, height: 110)
                Image(systemName: "drop.fill")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [entry.theme.accent, entry.theme.accent.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: entry.theme.accent.opacity(0.5), radius: 10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Water Eject")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.theme.secondaryText)
                Text("Tap to start")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(entry.theme.primaryText)
                Text("165 Hz tone, 30s")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(entry.theme.secondaryText)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Turn volume up for best results")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(entry.theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var circularLock: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Water")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
        }
    }
}
