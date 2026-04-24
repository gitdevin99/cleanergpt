import Foundation
import UIKit
import WidgetKit

/// Samples live device state (battery, storage, thermal) and writes it into
/// the App Group via `SharedDataStore`, then nudges WidgetKit to reload the
/// timelines so the Home-Screen widgets pick up the new numbers immediately.
///
/// Call `refresh()` after any scan, any storage-changing action, and on
/// every `UIApplication.didBecomeActiveNotification` (debounced).
@MainActor
final class SharedSnapshotWriter {
    static let shared = SharedSnapshotWriter()
    private init() {}

    // Debounce: writing more than once every few seconds is pointless.
    private var lastWriteAt: Date = .distantPast
    private let minInterval: TimeInterval = 3

    func refresh(force: Bool = false) {
        if !force && Date().timeIntervalSince(lastWriteAt) < minInterval {
            return
        }
        lastWriteAt = Date()

        let battery = sampleBattery()
        let storage = sampleStorage()
        let thermal = sampleThermal()

        SharedDataStore.update { snap in
            snap.battery = battery
            snap.storage = storage
            snap.thermal = thermal
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Call after a cleaning action so the Last Scan widget stays fresh.
    func recordScan(freedBytes: Int64) {
        SharedDataStore.update { snap in
            var history = snap.lastScan?.history ?? []
            history.insert(.init(date: Date(), freedBytes: freedBytes), at: 0)
            if history.count > 5 { history.removeLast(history.count - 5) }
            snap.lastScan = SharedDataStore.LastScanInfo(
                date: Date(),
                freedBytes: freedBytes,
                history: history
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Samplers

    private func sampleBattery() -> SharedDataStore.BatteryInfo {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = Double(UIDevice.current.batteryLevel)   // -1 when unknown (simulator)
        let stateString: String
        switch UIDevice.current.batteryState {
        case .charging: stateString = "charging"
        case .full:     stateString = "full"
        case .unplugged: stateString = "unplugged"
        case .unknown:  stateString = "unknown"
        @unknown default: stateString = "unknown"
        }
        return SharedDataStore.BatteryInfo(
            level: level,
            state: stateString,
            isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            minutesToFull: nil
        )
    }

    private func sampleStorage() -> SharedDataStore.StorageInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: [URLResourceKey] = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        let values = try? url.resourceValues(forKeys: Set(keys))
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        // `volumeAvailableCapacityForImportantUsage` is the number iOS shows
        // in Settings → General → iPhone Storage. Fall back if the key is
        // somehow unavailable on this device.
        let available: Int64
        if let v = values?.volumeAvailableCapacityForImportantUsage, v > 0 {
            available = v
        } else if let v = values?.volumeAvailableCapacity {
            available = Int64(v)
        } else {
            available = 0
        }
        let used = max(total - available, 0)
        return SharedDataStore.StorageInfo(
            usedBytes: used,
            totalBytes: total,
            byCategory: [:] // Category breakdown is populated by AppFlow when scans finish.
        )
    }

    private func sampleThermal() -> SharedDataStore.ThermalInfo {
        let stateString: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:   stateString = "nominal"
        case .fair:      stateString = "fair"
        case .serious:   stateString = "serious"
        case .critical:  stateString = "critical"
        @unknown default: stateString = "nominal"
        }
        return SharedDataStore.ThermalInfo(state: stateString, batteryHealthPercent: nil)
    }
}
