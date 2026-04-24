import Foundation

/// Widget-extension copy of the App Group reader. The main-app target owns
/// `CleanupClone/Core/SharedDataStore.swift`; this file provides the same
/// API for the widget process without pulling the entire app target into
/// the extension build. Schema must stay in sync — if you edit one, edit
/// both. (Keeping them as twins is cheaper than exposing a shared Swift
/// framework target just for one file.)
public enum SharedDataStore {
    public static let appGroupID = "group.com.sanjana.cleanupclone"
    private static let fileName = "snapshot.json"

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
        public var level: Double
        public var state: String
        public var isLowPower: Bool
        public var minutesToFull: Int?
        public static let empty = BatteryInfo(level: -1, state: "unknown", isLowPower: false, minutesToFull: nil)
    }

    public struct StorageInfo: Codable, Equatable, Sendable {
        public var usedBytes: Int64
        public var totalBytes: Int64
        public var byCategory: [String: Int64]

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
        public var history: [HistoryEntry]

        public struct HistoryEntry: Codable, Equatable, Sendable {
            public var date: Date
            public var freedBytes: Int64
        }
    }

    public struct ThermalInfo: Codable, Equatable, Sendable {
        public var state: String
        public var batteryHealthPercent: Int?
        public static let empty = ThermalInfo(state: "nominal", batteryHealthPercent: nil)
    }

    public static func load() -> Snapshot {
        guard let url = fileURL() else { return .empty }
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Snapshot.self, from: data)) ?? .empty
    }

    private static func fileURL() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        return container.appendingPathComponent(fileName, isDirectory: false)
    }
}
