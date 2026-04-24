import Foundation
import UIKit

/// Lightweight read/write layer over the shared App Group container.
///
/// Both the main CleanupClone app and the CleanerWidgets extension use this
/// type. The app writes whenever its storage / battery / scan state changes;
/// the widgets read on every timeline refresh.
///
/// The on-disk representation is a single JSON file (`snapshot.json`) inside
/// the App Group container. We deliberately avoid `UserDefaults(suiteName:)`
/// for payloads this structured — `UserDefaults` is a KV store meant for
/// small scalars, not a 2-level nested object, and its cross-process sync
/// guarantees are fuzzier than a plain file write.
public enum SharedDataStore {
    /// Must match the `com.apple.security.application-groups` entry in the
    /// entitlements of BOTH the app target and the widget extension target.
    public static let appGroupID = "group.com.sanjana.cleanupclone"

    private static let fileName = "snapshot.json"

    // MARK: - Model

    public struct Snapshot: Codable, Equatable, Sendable {
        public var battery: BatteryInfo
        public var storage: StorageInfo
        public var lastScan: LastScanInfo?
        public var thermal: ThermalInfo
        public var updatedAt: Date

        public static let empty = Snapshot(
            battery: .empty,
            storage: .empty,
            lastScan: nil,
            thermal: .empty,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    public struct BatteryInfo: Codable, Equatable, Sendable {
        public var level: Double          // 0.0 ... 1.0, or -1 if unknown
        public var state: String          // "charging" | "full" | "unplugged" | "unknown"
        public var isLowPower: Bool
        public var minutesToFull: Int?    // nil when unavailable

        public static let empty = BatteryInfo(level: -1, state: "unknown", isLowPower: false, minutesToFull: nil)
    }

    public struct StorageInfo: Codable, Equatable, Sendable {
        public var usedBytes: Int64
        public var totalBytes: Int64
        public var byCategory: [String: Int64]   // "photos" | "videos" | "apps" | "other" | ...

        public var freeBytes: Int64 { max(totalBytes - usedBytes, 0) }
        public var usedFraction: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(usedBytes) / Double(totalBytes)
        }

        public static let empty = StorageInfo(usedBytes: 0, totalBytes: 0, byCategory: [:])
    }

    public struct LastScanInfo: Codable, Equatable, Sendable {
        public var date: Date
        public var freedBytes: Int64
        public var history: [HistoryEntry]      // last ~5 scans, newest first

        public struct HistoryEntry: Codable, Equatable, Sendable {
            public var date: Date
            public var freedBytes: Int64
            public init(date: Date, freedBytes: Int64) {
                self.date = date
                self.freedBytes = freedBytes
            }
        }

        public init(date: Date, freedBytes: Int64, history: [HistoryEntry] = []) {
            self.date = date
            self.freedBytes = freedBytes
            self.history = history
        }
    }

    public struct ThermalInfo: Codable, Equatable, Sendable {
        public var state: String                 // "nominal" | "fair" | "serious" | "critical"
        public var batteryHealthPercent: Int?    // 0-100 if known
        public static let empty = ThermalInfo(state: "nominal", batteryHealthPercent: nil)
    }

    // MARK: - Public API

    /// Returns the current snapshot. Always succeeds — if anything is
    /// unreadable or missing, returns `Snapshot.empty` so callers (esp. the
    /// widget) never have to handle the nil case.
    public static func load() -> Snapshot {
        guard let url = fileURL() else { return .empty }
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder.shared.decode(Snapshot.self, from: data)) ?? .empty
    }

    /// Overwrites the snapshot atomically. Returns `true` on success.
    @discardableResult
    public static func save(_ snapshot: Snapshot) -> Bool {
        guard let url = fileURL() else { return false }
        guard let data = try? JSONEncoder.shared.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Convenience for the app: read, mutate, write.
    @discardableResult
    public static func update(_ mutate: (inout Snapshot) -> Void) -> Bool {
        var snap = load()
        mutate(&snap)
        snap.updatedAt = Date()
        return save(snap)
    }

    // MARK: - Private

    private static func fileURL() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            return nil
        }
        return container.appendingPathComponent(fileName, isDirectory: false)
    }
}

// MARK: - JSON coders

private extension JSONEncoder {
    static let shared: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()
}

private extension JSONDecoder {
    static let shared: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()
}
