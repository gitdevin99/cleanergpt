import WidgetKit

/// Every data-driven widget shares the same entry type — a theme + a
/// snapshot of the App Group state at the time the timeline was generated.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedDataStore.Snapshot
    let theme: WidgetTheme

    static let placeholder = SnapshotEntry(
        date: Date(),
        snapshot: .empty,
        theme: .aqua
    )

    static let preview = SnapshotEntry(
        date: Date(),
        snapshot: SharedDataStore.Snapshot(
            battery: SharedDataStore.BatteryInfo(
                level: 0.78, state: "charging", isLowPower: false, minutesToFull: 42
            ),
            storage: SharedDataStore.StorageInfo(
                usedBytes: 180 * 1_000_000_000,
                totalBytes: 256 * 1_000_000_000,
                byCategory: [
                    "photos": 82 * 1_000_000_000,
                    "videos": 48 * 1_000_000_000,
                    "apps":   32 * 1_000_000_000,
                    "other":  18 * 1_000_000_000
                ]
            ),
            lastScan: SharedDataStore.LastScanInfo(
                date: Date().addingTimeInterval(-3 * 86400),
                freedBytes: 4_100_000_000,
                history: []
            ),
            thermal: SharedDataStore.ThermalInfo(state: "nominal", batteryHealthPercent: 94),
            updatedAt: Date()
        ),
        theme: .aqua
    )
}

/// A timeline provider that simply samples the App Group every 15 minutes.
/// Each data widget wires this in — they differ only in their entry view.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
            return
        }
        completion(SnapshotEntry(
            date: Date(),
            snapshot: SharedDataStore.load(),
            theme: WidgetTheme.current()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snap = SharedDataStore.load()
        let theme = WidgetTheme.current()
        let entry = SnapshotEntry(date: now, snapshot: snap, theme: theme)
        // Refresh every 15 minutes. The app also nudges via
        // WidgetCenter.reloadAllTimelines after any scan or state change,
        // so this is really a fallback for quiet periods.
        let nextRefresh = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}
