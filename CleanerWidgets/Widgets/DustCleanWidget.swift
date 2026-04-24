import SwiftUI
import WidgetKit

/// Dust-cleaning widget.
///
/// Tapping the widget opens the host app via a `cleanup://` deep link;
/// the app then starts the 1–6 kHz sweep through `SharedToneEngine`
/// and auto-suspends back to the Home Screen so audio keeps playing.
/// Keeping the action in the app (vs. `Button(intent:)` inside the
/// widget) avoids iOS's SpringBoard "RequestDenied" edge cases and
/// gives us one consistent code path for Dust / Water / Quick Clean.
struct DustCleanWidget: Widget {
    let kind = "DustCleanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            DustCleanView(entry: entry)
        }
        .configurationDisplayName("Dust Clean")
        .description("Tap to open Cleanup and shake dust out of your speaker.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

private struct DustCleanView: View {
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
        .widgetURL(URL(string: "cleanup://run/dust"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "wind")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(entry.theme.accent)
                Text("Dust Clean")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.theme.secondaryText)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(entry.theme.accentDim, lineWidth: 1)
                    .frame(width: 84, height: 84)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [entry.theme.accent, entry.theme.accent.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: entry.theme.accent.opacity(0.45), radius: 8)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text("Tap to clean")
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
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [entry.theme.accent, entry.theme.accent.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: entry.theme.accent.opacity(0.45), radius: 10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Dust Clean")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.theme.secondaryText)
                Text("Tap to start")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(entry.theme.primaryText)
                Text("1–6 kHz sweep, 30s")
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
                Image(systemName: "wind")
                    .font(.system(size: 18, weight: .bold))
                Text("Dust")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
        }
    }
}
